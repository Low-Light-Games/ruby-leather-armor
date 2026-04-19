# frozen_string_literal: true

module DungeonMaster
  # Mech-eval may emit npc_actions alongside player rolls. In active combat, only
  # immediate reactions (e.g. AoO before the turn advances) should run here; routine
  # NPC attacks are owned by world turn. Uses explicit model fields so we never
  # pass routine NPC actions through on a mistaken empty heuristic.
  module MechanicalEvaluationNpcActions
    module_function

    def filter_for_combat_finish(npc_actions, combat_active:)
      list = Array(npc_actions)
      return normalize_keys(list) unless combat_active

      list.filter_map do |action|
        next unless action.is_a?(Hash)

        h = action.deep_symbolize_keys
        next unless immediate_npc_action?(h)

        h
      end
    end

    def immediate_npc_action?(h)
      ActiveModel::Type::Boolean.new.cast(h[:immediate]) ||
        h[:timing].to_s == "immediate"
    end

    def normalize_keys(list)
      list.map { |a| a.is_a?(Hash) ? a.deep_symbolize_keys : a }
    end
  end
end
