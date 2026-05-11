# frozen_string_literal: true

module Combat
  module WorldTurn
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
        ns  = (next_state_slice || {}).deep_stringify_keys

        current_turn = ns.key?("current_turn") ? ns["current_turn"] : ctx["current_turn"]
        active       = ns.key?("active")        ? ns["active"]        : (ctx["active"] != false)
        round        = ns.key?("round")         ? ns["round"]         : ctx["round"]

        participants = Array(ctx["participants"]).map { |p| rebuild_participant_row(p, adventure: adventure, sheet: sheet) }

        out = Combat::Context.build(ctx,
          participants: participants, active: active, round: round, current_turn: current_turn)
        out = normalize_inactive_snapshot(out)

        if active && current_turn.present?
          out["action_economy"] = Battlefield::ActionEconomy.build_for_turn_holder(
            current_turn, combat_ctx: out.merge(ctx.slice("turn_order")))
        elsif out["active"] != false && ctx["action_economy"].present?
          out["action_economy"] = ctx["action_economy"]
        end
        out
      end

      def build_full(adventure:, sheet:, overrides: {})
        ctx          = adventure.combat_context.deep_stringify_keys
        participants = Array(ctx["participants"]).map { |p| rebuild_participant_row(p, adventure: adventure, sheet: sheet) }

        base = Combat::Context.build(ctx, participants: participants)
        base = normalize_inactive_snapshot(base)
        if base["active"] != false && ctx["action_economy"].present?
          base["action_economy"] = ctx["action_economy"]
        end
        Transformers::HashMerge.deep_merge_presence(base, overrides.deep_stringify_keys)
      end

      def rebuild_participant_row(p, adventure:, sheet:)
        Combat::Combatant.refresh_from_live_sources(p, adventure: adventure, sheet: sheet)
      end

      def normalize_inactive_snapshot(ctx)
        normalized = ctx.deep_stringify_keys
        return normalized unless normalized["active"] == false

        participants = Array(normalized["participants"]).filter_map do |participant|
          row = participant.deep_stringify_keys
          next row unless row["type"].to_s == "npc"

          next if row["hp"].to_i <= 0

          row
        end

        normalized.merge(
          "participants" => participants,
          "current_turn" => nil,
          "turn_order" => [],
          "action_economy" => nil,
          "battlefield_ref" => nil
        )
      end

    end
  end
end
