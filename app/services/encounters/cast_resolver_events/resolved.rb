# frozen_string_literal: true

module Encounters
  module CastResolverEvents
    INTENT_PREVIEW_LENGTH = 160

    class Resolved
      include Hashable

      attr_reader :intent, :ai_entries, :roster_member_ids, :roster_member_names

      def initialize(intent:, ai_entries:, roster_member_ids:, roster_member_names:)
        @intent              = intent.to_s.truncate(INTENT_PREVIEW_LENGTH)
        @ai_entries          = Array(ai_entries)
        @roster_member_ids   = Array(roster_member_ids)
        @roster_member_names = Array(roster_member_names)
      end
    end
  end
end
