# frozen_string_literal: true

module Encounters
  module CastResolverEvents
    class Overspawn
      include Hashable

      attr_reader :adventure_id, :member_count, :threshold, :intent

      def initialize(adventure_id:, member_count:, threshold:, intent:)
        @adventure_id = adventure_id
        @member_count = member_count
        @threshold    = threshold
        @intent       = intent.to_s.truncate(CastResolverEvents::INTENT_PREVIEW_LENGTH)
      end
    end
  end
end
