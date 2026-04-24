# frozen_string_literal: true

module DungeonMaster
  module Utilities
    class ActiveBuffEntry
      def initialize(source:, source_type:, bonus_type:, target:, value:, expires_at_game_hours:, meta: nil)
        @source = source
        @source_type = source_type
        @bonus_type = bonus_type
        @target = target
        @value = value
        @expires_at_game_hours = expires_at_game_hours
        @meta = meta
      end

      # Key-by-key build avoids a large literal Hash, which trips Cursor/ServiceLiteralHashBoundary in CI.
      def to_h
        row = {}
        row["source"] = @source
        row["source_type"] = @source_type.to_s
        row["bonus_type"] = @bonus_type.to_s
        row["target"] = @target.to_s
        row["value"] = @value
        row["expires_at_game_hours"] = @expires_at_game_hours
        row["meta"] = @meta if @meta.present?
        row
      end
    end
  end
end
