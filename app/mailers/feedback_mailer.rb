# frozen_string_literal: true

class FeedbackMailer < ApplicationMailer
  def new_feedback(feedback)
    @feedback = feedback
    mail(
      to: "feedback@leatherarmor.io",
      subject: "New feedback from #{feedback.user&.email || 'anonymous'}"
    )
  end
end
