# frozen_string_literal: true

# Async narrator for the End Turn round log (PR-G of the
# combat-determinism arc — see docs/combat_redesign.md).
#
# Combat::Resolvers::EndPlayerTurn enqueues this job after the round resolves
# so the HTTP response can return immediately. The job loads the
# adventure, builds an AiClient, asks Combat::Narrator for a paragraph,
# persists it as a DM message, and broadcasts the new message so the
# chat updates without a refresh.
class CombatNarratorJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(adventure_id, round, npc_events)
    adventure = Adventure.find(adventure_id)
    sheet = adventure.adventure_sheets.first
    return unless sheet

    config = DmConfig.instance
    return unless config.combat_narrator_enabled?

    ai = DungeonMaster::AiClient.new(config)
    paragraph = Combat::Narrator.call(
      adventure: adventure, sheet: sheet, ai: ai, config: config,
      round: round, npc_events: npc_events
    )
    return if paragraph.blank?

    message = persist_message!(adventure, paragraph, round)
    broadcast(adventure, message)
  end

  private

  def persist_message!(adventure, paragraph, round)
    adventure.adventure_messages.create!(
      role: 'dm',
      content: paragraph,
      message_type: 'narrative',
      metadata: { 'combat_narrator' => true, 'round' => round }
    )
  end

  def broadcast(adventure, message)
    AdventureChannel.broadcast_to(adventure, {
                                    type: 'pipeline_result',
                                    messages: [DungeonMasterService.message_json(message)]
                                  })
  rescue StandardError => e
    ApplicationErrorReporter.notify(e, context: { source: 'combat_narrator_broadcast', adventure_id: adventure.id })
  end
end
