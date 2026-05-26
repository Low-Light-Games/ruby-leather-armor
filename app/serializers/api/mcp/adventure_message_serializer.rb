# frozen_string_literal: true

module Api
  module Mcp
    class AdventureMessageSerializer
      def self.call(message, verbose: false)
        {
          id: message.id,
          adventure_id: message.adventure_id,
          user_id: message.user_id,
          role: message.role,
          message_type: message.message_type,
          content: message.content,
          created_at: message.created_at,
          updated_at: verbose ? message.updated_at : nil
        }.compact
      end
    end
  end
end
