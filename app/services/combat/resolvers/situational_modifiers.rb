# frozen_string_literal: true

module Combat
  module Resolvers
    # Per-attack situational state (flanking + cover) — bundled together
    # so the resolver can carry the boolean and the numeric bonus
    # together instead of as four loose locals.
    class SituationalModifiers
      attr_reader :flanking, :flanking_bonus, :cover, :cover_bonus

      def self.zero
        new(flanking: false, cover: 0)
      end

      def initialize(flanking:, cover:)
        @flanking = flanking
        @flanking_bonus = flanking ? Combat::Rules::FLANKING_BONUS : 0
        @cover = cover
        @cover_bonus = cover
      end

      def to_h
        {
          flanking: flanking,
          flanking_bonus: flanking_bonus,
          cover: cover,
          cover_bonus: cover_bonus
        }
      end
    end
  end
end
