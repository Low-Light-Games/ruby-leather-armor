# frozen_string_literal: true

module Battlefield
  module ActionEconomy
    class Snapshot
      def self.from_combat_context(combat_context)
        ctx = combat_context.is_a?(Hash) ? combat_context : {}
        new(ctx['action_economy'])
      end

      def initialize(raw)
        @raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
      end

      def standard_available?
        truthy?(@raw['standard_available']) && !truthy?(@raw['full_round_claimed'])
      end

      def move_available?
        truthy?(@raw['move_available'])
      end

      def swift_available?
        truthy?(@raw['swift_available'])
      end

      def full_round_claimed?
        truthy?(@raw['full_round_claimed'])
      end

      def empty?
        @raw.empty?
      end

      def to_h
        @raw
      end

      private

      def truthy?(value)
        value == true || value.to_s == 'true'
      end
    end
  end
end
