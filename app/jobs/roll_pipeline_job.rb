# frozen_string_literal: true

class RollPipelineJob < ApplicationJob
  queue_as :dm_pipeline
  discard_on ActiveRecord::RecordNotFound

  def perform(adventure_id, player_message_id, roll_results_text, user_id)
    adventure = Adventure.find(adventure_id)
    user = User.find(user_id)
    service = DungeonMasterService.new(adventure, user: user)

    result_messages = service.execute_rolls(roll_results_text, player_message_id: player_message_id)
    broadcast(adventure, result_messages, admin: user.admin?)
  rescue => e
    broadcast_error(adventure_id)
    raise
  end

  private

  def broadcast(adventure, messages, admin: false)
    serialized = messages.map { |m| DungeonMasterService.message_json(m, admin: admin) }
    AdventureChannel.broadcast_to(adventure, { type: "pipeline_result", messages: serialized })
  end

  def broadcast_error(adventure_id)
    adventure = Adventure.find_by(id: adventure_id)
    return unless adventure

    error_msg = adventure.adventure_messages.create!(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... Please try again.",
      message_type: "narrative",
      metadata: {})
    AdventureChannel.broadcast_to(adventure, {
      type: "pipeline_result",
      messages: [ DungeonMasterService.message_json(error_msg) ]
    })
  rescue StandardError => e
    ApplicationErrorReporter.notify(e, context: { source: "roll_pipeline_job_broadcast_error", adventure_id: adventure_id })
    nil
  end
end
