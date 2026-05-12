# frozen_string_literal: true

module Encounters
  module CastResolverEvents
    class DefaultFallback
      include Hashable

      attr_reader :name, :type, :count, :bestiary_entry_id

      def initialize(name:, type:, count:, bestiary_entry_id:)
        @name              = name
        @type              = type
        @count             = count
        @bestiary_entry_id = bestiary_entry_id
      end
    end
  end
end
