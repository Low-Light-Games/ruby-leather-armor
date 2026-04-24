# frozen_string_literal: true

module CharacterStats
  # PF1e-style stacking for persisted active_buff rows: same bonus_type → highest
  # value wins; distinct bonus_types → sum of each group's winner.
  module ActiveBuffStacking
    module_function

    def stacked_value_for_target(active_buffs, target)
      Array(active_buffs)
        .select { |b| b["target"].to_s == target.to_s }
        .group_by { |b| b["bonus_type"].to_s }
        .values
        .sum { |group| group.map { |b| b["value"].to_i }.max }
    end

    def max_per_bonus_type_for_target(active_buffs, target)
      Array(active_buffs)
        .select { |b| b["target"].to_s == target.to_s }
        .group_by { |b| b["bonus_type"].to_s }
        .transform_values { |group| group.map { |b| b["value"].to_i }.max }
    end
  end
end
