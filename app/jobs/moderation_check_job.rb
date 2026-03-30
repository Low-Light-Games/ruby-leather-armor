# frozen_string_literal: true

# Performs async moderation for trusted users.
#
# Trusted users bypass synchronous moderation to avoid pipeline latency,
# but their input is still checked after the fact. If flagged, strikes are
# applied and trust may be revoked per the moderation.yml thresholds.
class ModerationCheckJob < ApplicationJob
  queue_as :moderation
  discard_on ActiveRecord::RecordNotFound

  def perform(user_id, player_input)
    user = User.find(user_id)
    DungeonMaster::ModerationService.call(player_input, user: user)
  end
end
