# frozen_string_literal: true

module Encounters
  module CastResolverEvents
    class Overspawn
      attr_reader :adventure_id, :member_count, :threshold, :intent

      def initialize(adventure_id:, member_count:, threshold:, intent:)
        @adventure_id = adventure_id
        @member_count = member_count
        @threshold    = threshold
        @intent       = intent.to_s
      end

      def to_h
        {
          adventure_id: @adventure_id,
          member_count: @member_count,
          threshold:    @threshold,
          intent:       @intent.truncate(CastResolverEvents::INTENT_PREVIEW_LENGTH),
        }
      end
    end
  end
end
