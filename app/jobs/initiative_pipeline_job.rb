# frozen_string_literal: true

class InitiativePipelineJob < ApplicationJob
  queue_as :dm_pipeline

  def perform(adventure_id, player_message_id, player_initiative, user_id)
    adventure = Adventure.find(adventure_id)
    user = User.find(user_id)
    service = DungeonMasterService.new(adventure, user: user)

    result_messages = service.execute_initiative(player_initiative, player_message_id: player_message_id)
    broadcast(adventure, result_messages, admin: user.admin?)
  end

  private

  def broadcast(adventure, messages, admin: false)
    serialized = messages.map { |m| DungeonMasterService.message_json(m, admin: admin) }
    AdventureChannel.broadcast_to(adventure, { type: "pipeline_result", messages: serialized })
  end
end
