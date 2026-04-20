# frozen_string_literal: true

module DungeonMaster
  module Steps
    module SanityChecker
      class WorldConsistencyResult
        attr_reader :consistent, :reason, :dm_message, :referenced_entities

        def initialize(consistent:, reason:, dm_message:, referenced_entities:)
          @consistent = consistent == true
          @reason = reason
          @dm_message = dm_message
          @referenced_entities = referenced_entities
        end

        def to_h
          {
            consistent: consistent,
            reason: reason,
            dm_message: dm_message,
            referenced_entities: referenced_entities
          }
        end
      end
    end
  end
end
