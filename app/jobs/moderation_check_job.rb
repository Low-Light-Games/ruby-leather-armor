# frozen_string_literal: true

# Runs the moderation check asynchronously for trusted users.
# The pipeline proceeds without waiting; this job records any strikes
# and applies auto-ban / trust-revocation after the fact.
class ModerationCheckJob < ApplicationJob
  queue_as :dm_pipeline
  discard_on ActiveRecord::RecordNotFound

  def perform(user_id, player_input)
    user = User.find(user_id)
    Moderation::Service.call(player_input, user: user)
  end
end
