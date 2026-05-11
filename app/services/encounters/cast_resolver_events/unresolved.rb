# frozen_string_literal: true

module Encounters
  module CastResolverEvents
    class Unresolved
      attr_reader :name, :type, :count, :adventure_id

      def initialize(name:, type:, count:, adventure_id:)
        @name         = name
        @type         = type
        @count        = count
        @adventure_id = adventure_id
      end

      def to_h
        { name: @name, type: @type, count: @count, adventure_id: @adventure_id }
      end
    end
  end
end
