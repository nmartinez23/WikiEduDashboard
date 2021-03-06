# frozen_string_literal: true

#= Preview all emails at http://localhost:3000/rails/mailers/survey_mailer
class AlertPreview < ActionMailer::Preview
  def articles_for_deletion_alert
    AlertMailer.alert(Alert.where(type: 'ArticlesForDeletionAlert').last, example_user)
  end

  def no_enrolled_students_alert
    AlertMailer.alert(Alert.where(type: 'NoEnrolledStudentsAlert').last, example_user)
  end

  def untrained_students_alert
    AlertMailer.alert(Alert.where(type: 'UntrainedStudentsAlert').last, example_user)
  end

  def productive_course_alert
    AlertMailer.alert(Alert.where(type: 'ProductiveCourseAlert').last, example_user)
  end

  def continued_course_activity_alert
    AlertMailer.alert(Alert.where(type: 'ContinuedCourseActivityAlert').last, example_user)
  end

  private

  def example_user
    User.new(email: 'sage@example.com', username: 'Ragesoss')
  end
end
