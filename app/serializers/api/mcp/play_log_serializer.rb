# frozen_string_literal: true

module Api
  module Mcp
    class PlayLogSerializer
      def self.call(log)
        {
          id: log.id,
          adventure_id: log.adventure_id,
          player_message_id: log.player_message_id,
          registry_entry_uuid: log.registry_entry_uuid,
          event_type: log.event_type,
          status: log.status,
          dm_service: log.dm_service,
          prompt_summary: log.prompt_summary,
          created_at: log.created_at
        }
      end
    end
  end
end
