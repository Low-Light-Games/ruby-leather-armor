# frozen_string_literal: true

class FeedbacksController < ApplicationController
  RATE_LIMIT = 5
  RATE_WINDOW = 5.minutes

  def create
    if Feedback.where(user: current_user).where("created_at > ?", RATE_WINDOW.ago).count >= RATE_LIMIT
      render json: { error: "You've sent several messages recently. Please wait a few minutes." }, status: :too_many_requests
      return
    end

    feedback = Feedback.new(
      body: params[:body],
      page_url: params[:page_url],
      user_agent: request.user_agent,
      user: current_user
    )

    if feedback.save
      FeedbackMailer.new_feedback(feedback).deliver_later
      render json: { id: feedback.id }, status: :created
    else
      render json: { errors: feedback.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
