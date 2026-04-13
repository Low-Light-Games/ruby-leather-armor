# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # Code-only: combat end vs player interaction state (death/incapacitation) are separate concerns.
    module CombatEndResolver
      module_function

      def check_player_status(sheet)
        return :alive if sheet.hp > 0
        return :disabled if sheet.hp == 0
        return :dead if sheet.hp <= -sheet.constitution

        :dying
      end

      # @param adventure [Adventure]
      # @param sheet [Sheet] player character sheet
      # @return [Hash] :combat, :interaction, :player_status
      #
      # Combat ends only when the player is **dead** or every NPC is eliminated.
      # A *dying* player (negative HP, not yet at −CON) keeps combat active so that
      # the world turn can apply per-round bleed-out and stabilization rolls.
      def check_combat_end(adventure:, sheet:)
        player_status = check_player_status(sheet)
        npc_ids = combat_npc_sheet_ids(adventure)
        npcs = adventure.creature_sheets.where(id: npc_ids)

        all_npcs_down = if npc_ids.empty?
                          false
                        else
                          npcs.all? do |c|
                            c.hp <= 0 || (Array(c.conditions) & %w[dead fled surrendered]).any?
                          end
                        end

        combat = if player_status == :dead || all_npcs_down
                   reason = all_npcs_down ? :all_npcs_defeated : :player_death
                   { combat_active: false, combat_end_reason: reason }
                 else
                   { combat_active: true, combat_end_reason: nil }
                 end

        interaction = {
          player_death:         player_status == :dead,
          player_incapacitated: player_status == :dying
        }

        { combat: combat, interaction: interaction, player_status: player_status }
      end

      def combat_npc_sheet_ids(adventure)
        ctx = adventure.combat_context
        return [] unless ctx.is_a?(Hash)

        Array(ctx["participants"]).filter_map do |p|
          p = p.stringify_keys if p.respond_to?(:stringify_keys)
          sid = p["creature_sheet_id"]
          sid.to_i if sid.present?
        end.uniq
      end
    end
  end
end
