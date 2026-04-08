# frozen_string_literal: true

module DungeonMaster
  module AdventurePlay
    # JSON shape for AdventureMessage in cables / API responses.
    module MessageSerializer
      module_function

      def as_json(message, admin: false)
        json = {
          id: message.id,
          role: message.role,
          content: message.content,
          message_type: message.message_type,
          metadata: message.metadata,
          created_at: message.created_at
        }
        if admin && message.role != "player"
          json[:registry_entry_uuid] = message.metadata&.dig("registry_entry_uuid")
        end
        json
      end
    end
  end
end
