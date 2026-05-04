# frozen_string_literal: true

module Combat
  # Persists a player-visible combat_log message and broadcasts it on
  # the AdventureChannel so the chat feed updates live. Centralises the
  # seam used by the deterministic HUD path
  # (PlayerActionResolver + NpcTurn) — the free-text path already
  # persists combat_log lines via PipelineMessenger, but the
  # deterministic HUD path bypasses the pipeline entirely.
  module EventLog
    module_function

    # @param adventure [Adventure]
    # @param content [String] one-line, fact-shaped, dice-ful summary
    # @param user [User, nil] used only for admin gating in the broadcast payload
    def write!(adventure:, content:, user: nil)
      return if content.to_s.strip.empty?

      msg = adventure.adventure_messages.create!(
        role: 'dm', content: content.to_s.strip, message_type: 'combat_log'
      )
      broadcast(adventure, msg, user)
      msg
    rescue StandardError => e
      Rails.logger.warn("[Combat::EventLog] persist failed: #{e.message}")
      nil
    end

    # NpcTurnEvent::Attack hides its message under :outcome; the others
    # carry it at the top level. Centralised here so callers don't have
    # to know the shape.
    def message_for_npc_event(event)
      return nil unless event.is_a?(Hash)

      top = event[:message] || event['message']
      return top if top.to_s.strip.length.positive?

      outcome = event[:outcome] || event['outcome']
      outcome.is_a?(Hash) ? (outcome['message'] || outcome[:message]) : nil
    end

    def broadcast(adventure, msg, user)
      AdventureChannel.broadcast_to(
        adventure,
        type: 'pipeline_action_result',
        messages: [DungeonMaster::AdventurePlay::MessageSerializer.as_json(msg, admin: user&.admin?)]
      )
    rescue StandardError => e
      Rails.logger.warn("[Combat::EventLog] broadcast failed: #{e.message}")
    end
  end
end
