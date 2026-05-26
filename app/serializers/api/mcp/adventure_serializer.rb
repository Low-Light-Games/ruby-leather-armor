# frozen_string_literal: true

module Api
  module Mcp
    class AdventureSerializer
      def self.call(adventure, verbose: false)
        base = {
          id: adventure.id,
          user_id: adventure.user_id,
          user_email: adventure.user&.email,
          story_id: adventure.story_id,
          story_title: adventure.story&.title,
          discarded_at: adventure.discarded_at,
          ended_at: adventure.ended_at,
          end_reason: adventure.end_reason,
          created_at: adventure.created_at,
          updated_at: adventure.updated_at
        }
        if verbose
          base.merge!(
            current_location: adventure.current_location&.then { |l| { id: l.id, name: l.name } },
            directed_dm: adventure.directed_dm?,
            use_gamemaster_orchestrator: adventure.use_gamemaster_orchestrator?,
            combat_active: adventure.combat_active?
          )
        end
        base
      end
    end
  end
end
