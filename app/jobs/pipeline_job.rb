# frozen_string_literal: true

class PipelineJob < ApplicationJob
  queue_as :dm_pipeline
  discard_on ActiveRecord::RecordNotFound

  def perform(adventure_id, player_message_id, player_input, mode, user_id)
    log_queue_wait!(adventure_id: adventure_id, user_id: user_id)

    adventure = Adventure.find(adventure_id)
    user = User.find(user_id)
    service = DungeonMasterService.new(adventure, user: user)

    result_messages = service.execute_prompt(player_input, player_message_id: player_message_id, mode: mode)
    broadcast(adventure, result_messages, admin: user.admin?)
  rescue => e
    broadcast_error(adventure_id)
    raise
  end

  private

  QUEUE_WAIT_TARGET_MS = 2_000

  def log_queue_wait!(adventure_id:, user_id:)
    return if enqueued_at.blank?

    enqueued_time = enqueued_at.is_a?(Time) ? enqueued_at : Time.zone.parse(enqueued_at.to_s)
    return unless enqueued_time

    queue_wait_ms = ((Time.current - enqueued_time) * 1000).round
    payload = {
      adventure_id: adventure_id,
      user_id: user_id,
      queue_wait_ms: queue_wait_ms,
      queue_wait_target_ms: QUEUE_WAIT_TARGET_MS,
      within_target: queue_wait_ms <= QUEUE_WAIT_TARGET_MS
    }

    ActiveSupport::Notifications.instrument("dm.prompt_queue_wait", payload)
    Rails.logger.info("[DM queue_wait] #{payload}")
  rescue StandardError => e
    ApplicationErrorReporter.notify(e, context: { source: "pipeline_job_queue_wait", adventure_id: adventure_id, user_id: user_id })
  end

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
    ApplicationErrorReporter.notify(e, context: { source: "pipeline_job_broadcast_error", adventure_id: adventure_id })
    nil
  end
end
