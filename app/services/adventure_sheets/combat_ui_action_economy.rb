# frozen_string_literal: true

module AdventureSheets
  # Server-side action economy for direct sheet mutations during combat (equip, etc.).
  class CombatUiActionEconomy
    class Error < StandardError; end

    class << self
      def enforce_player_turn!(adventure:, sheet:)
        return unless adventure.combat_active?

        ctx = adventure.combat_context
        turn = ctx["current_turn"].to_s
        player_name = DungeonMaster::Utilities::CombatTurnCalculator::PLAYER_NAME
        raise Error, "Only on your turn" unless turn == player_name
      end

      def apply_equip_toggle!(adventure:, sheet:)
        return unless adventure.combat_active?

        enforce_player_turn!(adventure: adventure, sheet: sheet)

        adventure.with_lock do
          ctx = adventure.combat_context.deep_dup.deep_stringify_keys
          econ = ctx["action_economy"]
          raise Error, "Combat action pool missing — wait for turn sync" if econ.blank?

          delta = DungeonMaster::Battlefield::ActionEconomy.equip_toggle_cost_delta
          new_econ = DungeonMaster::Battlefield::ActionEconomy.apply_delta!(econ, delta)
          ctx["action_economy"] = new_econ
          adventure.update!(combat_context: ctx)
        end
      end
    end
  end
end
