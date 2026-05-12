# frozen_string_literal: true

module Encounters
  module CastResolverEvents
    class Unresolved
      include Hashable

      attr_reader :name, :type, :count, :adventure_id

      def initialize(name:, type:, count:, adventure_id:)
        @name         = name
        @type         = type
        @count        = count
        @adventure_id = adventure_id
      end
    end
  end
end
