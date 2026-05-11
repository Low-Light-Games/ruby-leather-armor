# frozen_string_literal: true

module Combat
  module OpposedRollResolution
    class DcClampEvent
      attr_reader :skill, :ai_dc, :code_dc, :target_sheet_id

      def initialize(skill:, ai_dc:, code_dc:, target_sheet_id:)
        @skill           = skill
        @ai_dc           = ai_dc
        @code_dc         = code_dc
        @target_sheet_id = target_sheet_id
      end

      def to_h
        {
          skill:           @skill,
          ai_dc:           @ai_dc,
          code_dc:         @code_dc,
          target_sheet_id: @target_sheet_id,
        }
      end

      def to_sentry_context
        to_h.merge(source: "opposed_roll_dc_clamp")
      end
    end
  end
end
