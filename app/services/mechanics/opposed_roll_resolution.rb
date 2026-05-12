# frozen_string_literal: true

module Mechanics
  module OpposedRollResolution
    SKILL_TO_OPPOSING_SKILL = {
      "stealth"          => "Perception",
      "bluff"            => "Sense Motive",
      "diplomacy"        => "Sense Motive",
      "disguise"         => "Perception",
      "sleight of hand"  => "Perception",
      "intimidate"       => "Sense Motive",
    }.freeze

    DEFENDER_PASSIVE_BASE = 10

    def self.opposed?(skill)
      SKILL_TO_OPPOSING_SKILL.key?(normalize(skill))
    end

    def self.code_dc_for(skill:, target_sheet:)
      opposing = SKILL_TO_OPPOSING_SKILL[normalize(skill)]
      return nil unless opposing

      return nil unless target_sheet&.derived_stats.is_a?(Hash)

      skills = Array(target_sheet.derived_stats["skills"])
      entry  = skills.find { |s| s.is_a?(Hash) && s["name"].to_s == opposing }
      total  = entry ? entry["total"].to_i : 0
      DEFENDER_PASSIVE_BASE + total
    end

    # @param roll [Hash]
    # @param target_sheet [AdventureActorSheet, nil]
    # @param log [#play_log!, nil]
    # @return [Integer, nil]
    def self.resolve_dc(roll:, target_sheet:, log: nil)
      return roll[:dc] unless roll.is_a?(Hash)

      skill = roll[:skill].to_s
      return roll[:dc] unless opposed?(skill)

      return roll[:dc] unless target_sheet

      code_dc = code_dc_for(skill: skill, target_sheet: target_sheet)
      return roll[:dc] unless code_dc

      report_dc_clamp_violation!(skill: skill, ai_dc: roll[:dc], code_dc: code_dc,
                                 target_sheet: target_sheet, log: log)
      code_dc
    end

    def self.normalize(skill)
      skill.to_s.downcase.strip
    end

    def self.report_dc_clamp_violation!(skill:, ai_dc:, code_dc:, target_sheet:, log:)
      return if ai_dc.blank?

      event = DcClampEvent.new(
        skill: skill, ai_dc: ai_dc, code_dc: code_dc, target_sheet_id: target_sheet.id,
      )
      ApplicationErrorReporter.notify(
        RuntimeError.new(
          "RollRequest emitted dc=#{ai_dc.inspect} for opposed skill #{skill.inspect} " \
          "(code resolved dc=#{code_dc} from target sheet)"
        ),
        context: event.to_sentry_context,
      )
      log&.play_log!(
        "opposed_roll_dc_clamp",
        "OpposedRollResolution: clamped AI dc=#{ai_dc.inspect} for opposed skill #{skill.inspect}; using code dc=#{code_dc}",
        parsed_response: event.to_h,
      )
    end
  end
end
