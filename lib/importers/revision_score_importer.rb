# frozen_string_literal: true
require "#{Rails.root}/lib/ores_api"

#= Imports revision scoring data from ores.wikimedia.org
# As of July 2016, this only applies to English Wikipedia.
# French and other Wikipedias also have wp10 models for ORES, they don't match
# enwiki version.
class RevisionScoreImporter
  ################
  # Entry points #
  ################
  def initialize
    @wiki = Wiki.find_by(language: 'en', project: 'wikipedia')
    @ores_api = OresApi.new(@wiki)
  end

  def update_revision_scores(revisions=nil)
    revisions = revisions&.select { |rev| rev.wiki_id == @wiki.id }
    revisions ||= unscored_mainspace_userspace_and_draft_revisions

    batches = revisions.count / 50 + 1
    revisions.each_slice(50).with_index do |rev_batch, i|
      Rails.logger.debug "Pulling revisions: batch #{i + 1} of #{batches}"
      get_and_save_scores rev_batch
    end
  end

  def update_all_revision_scores_for_articles(articles)
    page_ids = articles.map(&:mw_page_id)
    revisions = Revision.where(wiki_id: @wiki.id, mw_page_id: page_ids)
    update_revision_scores revisions

    first_revisions = []
    page_ids.each do |id|
      first_revisions << Revision.where(mw_page_id: id, wiki_id: @wiki.id).first
    end

    first_revisions.each { |revision| update_wp10_previous(revision) }
  end

  ##################
  # Helper methods #
  ##################
  private

  # This should take up to 50 rev_ids per batch
  def get_and_save_scores(rev_batch)
    scores, features = {}, {}
    threads = rev_batch.each_with_index.map do |revision, i|
      Thread.new(i) do
        ores_data = @ores_api.get_revision_data(revision.mw_rev_id)
        scores.merge!(extract_score(ores_data))
        features.merge!(extract_features(ores_data))
      end
    end
    threads.each(&:join)
    save_scores(scores, features)
  end

  def update_wp10_previous(revision)
    parent_id = get_parent_id revision
    ores_data = @ores_api.get_revision_data(parent_id)
    score = extract_score ores_data
    return unless score[parent_id.to_s]&.key?('probability')
    probability = score[parent_id.to_s]['probability']
    revision.wp10_previous = en_wiki_weighted_mean_score probability
    revision.save
  end

  def unscored_mainspace_userspace_and_draft_revisions
    Revision.joins(:article)
            .where(wp10: nil, wiki_id: @wiki.id, deleted: false)
            .where(articles: { namespace: [0, 2, 118] })
  end

  def save_scores(scores, features)
    scores.each do |rev_id, score|
      next unless score&.key?('probability')
      revision = Revision.find_by(mw_rev_id: rev_id.to_i, wiki_id: @wiki.id)
      revision.wp10 = en_wiki_weighted_mean_score score['probability']
      revision.features = features[rev_id]
      revision.save
    end
  end

  def get_parent_id(revision)
    require "#{Rails.root}/lib/wiki_api"

    rev_id = revision.mw_rev_id
    rev_query = parent_revision_query(rev_id)
    response = WikiApi.new(revision.wiki).query rev_query
    prev_id = response.data['pages'].values[0]['revisions'][0]['parentid']
    prev_id
  end

  def parent_revision_query(rev_id)
    { prop: 'revisions',
      revids: rev_id,
      rvprop: 'ids' }
  end

  WP10_WEIGHTING = { 'FA'    => 100,
                     'GA'    => 80,
                     'B'     => 60,
                     'C'     => 40,
                     'Start' => 20,
                     'Stub'  => 0 }.freeze
  def en_wiki_weighted_mean_score(probability)
    mean = 0
    WP10_WEIGHTING.each do |rating, weight|
      mean += probability[rating] * weight
    end
    mean
  end

  def extract_score(ores_data)
    return ores_data if ores_data.blank?
    scores = ores_data['scores']['enwiki']['wp10']['scores']
    scores || {}
  end

  def extract_features(ores_data)
    return ores_data if ores_data.blank?
    features = ores_data['scores']['enwiki']['wp10']['features']
    features || {}
  end
end
