# frozen_string_literal: true

module DungeonMaster
  module Rolls
    # Player-facing line built from mechanical summary strings on a roll_request.
    module RollExplanation
      module_function

      DEFAULT = "The DM awaits your rolls..."
      NO_MECHANICAL_INVOLVEMENT = "(no mechanical involvement in this domain)"

      def from_summaries(ruling_summaries)
        return DEFAULT if ruling_summaries.blank?

        Array(ruling_summaries)
          .map { |s| s.to_s.sub(/\A\[\w+\]\s*/, "") }
          .reject { |s| s.to_s.strip.casecmp(NO_MECHANICAL_INVOLVEMENT).zero? }
          .join(" ")
          .presence || DEFAULT
      end
    end
  end
end
