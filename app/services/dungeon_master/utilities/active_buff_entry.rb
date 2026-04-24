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

      def to_h
        {
          "source" => @source,
          "source_type" => @source_type.to_s,
          "bonus_type" => @bonus_type.to_s,
          "target" => @target.to_s,
          "value" => @value,
          "expires_at_game_hours" => @expires_at_game_hours,
        }.tap do |row|
          row["meta"] = @meta if @meta.present?
        end
      end
    end
  end
end
