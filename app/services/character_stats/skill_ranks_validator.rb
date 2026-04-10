# frozen_string_literal: true

module CharacterStats
  # Server-side Pathfinder 1e skill rank rules (budget, per-rank cost, max ranks per skill).
  # Mirrors app/javascript/rules/pathfinder_skill_ranks.ts — keep in sync.
  class SkillRanksValidator
    VALID_SKILL_NAMES = GameRules::SKILLS.map { |s| s[:name] }.freeze

    class << self
      def errors_for(source)
        return [] unless source.class.column_names.include?("skill_ranks")

        ranks = normalize_ranks(source.skill_ranks)
        return [] if ranks.empty?

        class_id = source.character_class.to_s.downcase.presence
        if class_id.blank?
          return ["Choose a character class before assigning skill ranks."]
        end

        skill_points_base = GameRules::CLASS_DATA[class_id]&.fetch(:skill_points, nil)
        if skill_points_base.nil?
          return ["Unknown character class — cannot validate skill ranks."]
        end

        errors = []
        ranks.each_key do |name|
          errors << "Unknown skill: #{name}" unless VALID_SKILL_NAMES.include?(name)
        end
        return errors if errors.any?

        level = [source.level.to_i, 1].max
        int_mod = Calculator.intelligence_modifier_for_skill_budget(source)
        budget = total_skill_points(level, int_mod, skill_points_base, source.race)

        spent = 0
        ranks.each do |skill_name, raw_n|
          n = raw_n.to_i
          if n.negative?
            errors << "Skill ranks cannot be negative (#{skill_name})."
            next
          end
          cap = max_ranks_cap(skill_name, class_id, level)
          if n > cap
            errors << "#{skill_name} has #{n} ranks but the maximum at level #{level} is #{cap}."
          end
          spent += rank_point_cost(skill_name, class_id) * n
        end

        if spent > budget
          errors << "Skill points spent (#{spent}) exceed your budget (#{budget})."
        end

        errors
      end

      private

      def normalize_ranks(raw)
        return {} unless raw.is_a?(Hash)

        raw.each_with_object({}) do |(k, v), h|
          n = v.to_i
          h[k.to_s] = n if n.positive?
        end
      end

      def rank_point_cost(skill_name, class_id)
        return 2 if class_id.blank?

        list = ClassSkillsData::LISTS[class_id]
        list&.include?(skill_name) ? 1 : 2
      end

      def max_ranks_cap(skill_name, class_id, level)
        per_level_cap = level + 3
        return (per_level_cap / 2) if class_id.blank?

        list = ClassSkillsData::LISTS[class_id]
        list&.include?(skill_name) ? per_level_cap : (per_level_cap / 2)
      end

      def total_skill_points(level, int_mod, skill_points_base, race_id)
        return 0 if level < 1

        per = [1, skill_points_base + int_mod].max
        human_extra = race_id.to_s == "human" ? level : 0
        (per * 4) + ((level - 1) * per) + human_extra
      end
    end
  end
end
