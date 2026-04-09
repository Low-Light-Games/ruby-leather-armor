# frozen_string_literal: true

module DungeonMaster
  module Rolls
    # Reads and mutates adventure state around mechanical pipeline pauses (rolls,
    # initiative) before resuming or starting a new player turn.
    module AdventureMechanicalState
      module_function

      def latest_roll_metadata(adventure)
        adventure.adventure_messages.for_message_types(["roll_request"]).newest_first.first&.metadata || {}
      end

      def latest_initiative_metadata(adventure)
        adventure.adventure_messages.for_message_types(["initiative_request"]).newest_first.first&.metadata || {}
      end

      def auto_finalize_pending_initiative!(adventure:, sheet:, log:)
        msgs = adventure.adventure_messages
        last_init_msg = msgs.for_message_types(["initiative_request"]).newest_first.first
        return unless last_init_msg&.metadata&.dig("creature_data")

        last_player_response = msgs.from_players
                                   .where("created_at > ?", last_init_msg.created_at)
                                   .newest_first.first
        return unless last_player_response
        return if last_player_response.message_type == "initiative_result"

        player_init = Utilities::Warmaster.auto_roll_player_initiative(sheet)
        creature_data = last_init_msg.metadata["creature_data"].map(&:deep_symbolize_keys)

        combat_data = Utilities::Warmaster.compute_combat_initialization(
          creature_data: creature_data, player_initiative: player_init)
        adventure.update!(combat_context: combat_data)

        log.log!(:info, "Auto-rolled player initiative (#{player_init}) — player ignored initiative prompt")
      end
    end
  end
end
