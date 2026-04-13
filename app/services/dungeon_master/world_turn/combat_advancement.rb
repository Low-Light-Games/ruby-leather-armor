# frozen_string_literal: true

module DungeonMaster
  module WorldTurn
    # combat_state_advancement payloads for ContextUpdate (canonical sheet merge).
    module CombatAdvancement
      module_function

      def merge_into_mutations(existing, advancement)
        m = existing.is_a?(Hash) ? existing.deep_dup : {}
        m.deep_stringify_keys.merge("combat_state_advancement" => advancement.deep_stringify_keys)
      end

      def merge_combat_end_into_advancement(advancement, end_info)
        adv = advancement.deep_stringify_keys
        adv["active"] = false if end_info[:combat][:combat_active] == false
        adv
      end

      def build_after_world_turn(next_state_slice, original_ctx, adventure:, sheet:)
        ctx = original_ctx.deep_stringify_keys
        ns = (next_state_slice || {}).deep_stringify_keys
        participants = Array(ctx["participants"]).map { |p| rebuild_participant_row(p, adventure: adventure, sheet: sheet) }
        current_turn = ns.key?("current_turn") ? ns["current_turn"] : ctx["current_turn"]
        active = ns.key?("active") ? ns["active"] : (ctx["active"] != false)
        out = {
          "turn_order" => ctx["turn_order"],
          "terrain_notes" => ctx["terrain_notes"],
          "active_effects" => ctx["active_effects"],
          "participants" => participants,
          "round" => ns.key?("round") ? ns["round"] : ctx["round"],
          "current_turn" => current_turn,
          "active" => active
        }
        out["battlefield_ref"] = ctx["battlefield_ref"] if ctx["battlefield_ref"].present?
        out["last_battlefield_ref"] = ctx["last_battlefield_ref"] if ctx["last_battlefield_ref"].present?
        if active && current_turn.present?
          out["action_economy"] = DungeonMaster::Battlefield::ActionEconomy.build_for_turn_holder(
            current_turn, combat_ctx: out.merge(ctx.slice("turn_order")), adventure: adventure, sheet: sheet
          )
        elsif ctx["action_economy"].present?
          out["action_economy"] = ctx["action_economy"]
        end
        out
      end

      def build_full(adventure:, sheet:, overrides: {})
        ctx = adventure.combat_context.deep_stringify_keys
        participants = Array(ctx["participants"]).map { |p| rebuild_participant_row(p, adventure: adventure, sheet: sheet) }
        base = {
          "active" => ctx["active"],
          "round" => ctx["round"],
          "current_turn" => ctx["current_turn"],
          "turn_order" => ctx["turn_order"],
          "participants" => participants,
          "terrain_notes" => ctx["terrain_notes"],
          "active_effects" => ctx["active_effects"]
        }
        base["battlefield_ref"] = ctx["battlefield_ref"] if ctx["battlefield_ref"].present?
        base["last_battlefield_ref"] = ctx["last_battlefield_ref"] if ctx["last_battlefield_ref"].present?
        base["action_economy"] = ctx["action_economy"] if ctx["action_economy"].present?
        Utilities::HashMerge.deep_merge_presence(base, overrides.deep_stringify_keys)
      end

      def rebuild_participant_row(p, adventure:, sheet:)
        c = Utilities::Combatant.from_context_hash(p)
        if c.player? && sheet
          Utilities::Combatant.from_player_sheet(sheet, initiative: c.initiative).to_context_hash
        elsif c.creature_sheet_id.present?
          cs = adventure.creature_sheets.find_by(id: c.creature_sheet_id)
          cs ? Utilities::Combatant.from_creature_sheet(cs, initiative: c.initiative).to_context_hash : c.to_context_hash
        else
          c.to_context_hash
        end
      end
    end
  end
end
