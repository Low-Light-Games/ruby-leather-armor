# frozen_string_literal: true

module Tools
  module RequestRoll
    class Result
      attr_reader :type, :skill, :save, :dc, :description, :rule_slug,
                  :take_10_eligible, :take_20_eligible,
                  :take_10_value, :take_20_value,
                  :situational_modifiers, :mechanical_summary, :request_id,
                  :target_creature_sheet_id

      def self.from_parsed(parsed, sheet:)
        parsed = (parsed || {}).deep_symbolize_keys
        mechanical_summary = parsed[:mechanical_summary].to_s.presence || "(no mechanical summary)"
        take_values = compute_take_values(parsed, sheet: sheet)

        new(
          type: parsed[:type].presence || "skill_check",
          skill: parsed[:skill],
          save: parsed[:save],
          dc: parsed[:dc],
          description: parsed[:description].presence || mechanical_summary,
          rule_slug: parsed[:rule_slug],
          take_10_eligible: parsed[:take_10_eligible] == true,
          take_20_eligible: parsed[:take_20_eligible] == true,
          take_10_value: take_values[:take_10_value],
          take_20_value: take_values[:take_20_value],
          situational_modifiers: PlayerTurn::Rolls::SituationalModifiers.normalize(parsed[:situational_modifiers]),
          mechanical_summary: mechanical_summary,
          target_creature_sheet_id: coerce_target_id(parsed[:target_creature_sheet_id])
        )
      end

      def self.compute_take_values(parsed, sheet:)
        stub = parsed.slice(:type, :skill).merge(type: parsed[:type].presence || "skill_check")
        PlayerTurn::Rolls::PlayerRolls.compute_take_values!([stub], sheet: sheet)
        stub.slice(:take_10_value, :take_20_value)
      end

      def self.coerce_target_id(raw)
        return nil if raw.nil? || raw == ""

        id = Integer(raw, exception: false)
        id&.positive? ? id : nil
      end

      def initialize(type:, skill:, save:, dc:, description:, rule_slug:,
                     take_10_eligible:, take_20_eligible:,
                     take_10_value:, take_20_value:,
                     situational_modifiers:, mechanical_summary:,
                     request_id: nil, target_creature_sheet_id: nil)
        @type = type
        @skill = skill
        @save = save
        @dc = dc
        @description = description
        @rule_slug = rule_slug
        @take_10_eligible = take_10_eligible
        @take_20_eligible = take_20_eligible
        @take_10_value = take_10_value
        @take_20_value = take_20_value
        @situational_modifiers = situational_modifiers
        @mechanical_summary = mechanical_summary
        @request_id = request_id || SecureRandom.uuid
        @target_creature_sheet_id = target_creature_sheet_id
      end

      def to_h
        {
          type: @type,
          skill: @skill,
          save: @save,
          dc: @dc,
          description: @description,
          rule_slug: @rule_slug,
          take_10_eligible: @take_10_eligible,
          take_20_eligible: @take_20_eligible,
          take_10_value: @take_10_value,
          take_20_value: @take_20_value,
          situational_modifiers: @situational_modifiers,
          mechanical_summary: @mechanical_summary,
          request_id: @request_id,
          target_creature_sheet_id: @target_creature_sheet_id
        }.compact
      end
    end
  end
end
