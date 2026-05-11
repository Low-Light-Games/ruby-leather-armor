# frozen_string_literal: true

module Encounters
  module CastResolverEvents
    INTENT_PREVIEW_LENGTH = 160

    class Resolved
      attr_reader :intent, :ai_entries, :roster_member_ids, :roster_member_names

      def initialize(intent:, ai_entries:, roster_member_ids:, roster_member_names:)
        @intent              = intent.to_s
        @ai_entries          = Array(ai_entries)
        @roster_member_ids   = Array(roster_member_ids)
        @roster_member_names = Array(roster_member_names)
      end

      def to_h
        {
          intent:              @intent.truncate(INTENT_PREVIEW_LENGTH),
          ai_entries:          @ai_entries,
          roster_member_ids:   @roster_member_ids,
          roster_member_names: @roster_member_names,
        }
      end
    end
  end
end
