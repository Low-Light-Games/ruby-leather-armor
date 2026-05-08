# frozen_string_literal: true

module Combat
  module EventLog
    module_function

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

    def write_npc_event!(adventure:, event:, user: nil)
      write!(adventure: adventure, content: extract_npc_event_message(event), user: user)
    end

    def extract_npc_event_message(event)
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
        messages: [Adventures::MessageSerializer.as_json(msg, admin: user&.admin?)]
      )
    rescue StandardError => e
      Rails.logger.warn("[Combat::EventLog] broadcast failed: #{e.message}")
    end
  end
end
