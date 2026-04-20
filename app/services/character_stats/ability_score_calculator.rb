# frozen_string_literal: true

module CharacterStats
  # Computes the ability score pipeline for a sheet-like source.
  #
  # Handles: racial modifiers, condition penalties, final ability scores,
  # ability modifiers, BAB, and base save progressions.
  #
  # Returns a plain Hash consumed by the Calculator orchestrator.
  class AbilityScoreCalculator
    include GameRules

    # @param source [Sheet, AdventureSheet, CreatureSheet]
    def initialize(source)
      @src = source
    end

    # @return [Hash] with keys:
    #   :race_info, :final_scores, :mods, :active_conditions, :bab, :good_saves
    def compute
      race_info  = RACE_DATA[@src.race] || RACE_DATA["human"]
      class_info = CLASS_DATA[@src.character_class]

      racial_mods   = compute_racial_mods(race_info)
      pre_condition = compute_final_scores(racial_mods)
      final_scores  = apply_condition_penalties(pre_condition)
      mods          = compute_ability_mods(final_scores)

      good_saves = class_info ? class_info[:good_saves] : []
      bab        = class_info ? compute_bab(class_info[:bab], @src.level) : 0

      {
        race_info:        race_info,
        class_info:       class_info,
        final_scores:     final_scores,
        mods:             mods,
        active_conditions: active_conditions,
        bab:              bab,
        good_saves:       good_saves,
      }
    end

    private

    # ── Conditions ──────────────────────────────────────────────────

    def active_conditions
      @active_conditions ||= Array(@src.try(:conditions))
    end

    def apply_condition_penalties(scores)
      conds = active_conditions
      return scores if conds.empty?

      adjusted = scores.dup
      Conditions.effective_scores(conds).each do |ability, value|
        adjusted[ability] = value
      end
      Conditions.ability_penalties(conds).each do |ability, penalty|
        next if Conditions.effective_scores(conds).key?(ability)

        adjusted[ability] = (adjusted[ability] + penalty).clamp(0, 99)
      end
      adjusted
    end

    # ── Ability score pipeline ───────────────────────────────────────

    def compute_racial_mods(race_info)
      mods = ABILITIES.each_with_object({}) { |a, h| h[a] = 0 }
      (race_info[:fixed] || {}).each { |a, v| mods[a] += v }
      if race_info[:flex_count].to_i > 0 && @src.racial_bonus_attribute.present?
        mods[@src.racial_bonus_attribute] += 2
      end
      mods
    end

    def compute_final_scores(racial_mods)
      ABILITIES.each_with_object({}) do |a, h|
        h[a] = @src.send(a) + (racial_mods[a] || 0)
      end
    end

    def compute_ability_mods(final_scores)
      final_scores.transform_values { |v| ((v - 10).to_f / 2).floor }
    end

    # ── BAB & saves ─────────────────────────────────────────────────

    def compute_bab(progression, level)
      case progression
      when "full"  then level
      when "3/4"   then (level * 3 / 4.0).floor
      when "1/2"   then (level / 2.0).floor
      else 0
      end
    end
  end
end
