# frozen_string_literal: true

module DungeonMaster
  module Utilities
    class ActiveBuffEntry
      def initialize(source:, bonus_type:, target:, value:, expires_at_game_hours:, meta: nil)
        @source = source
        @bonus_type = bonus_type
        @target = target
        @value = value
        @expires_at_game_hours = expires_at_game_hours
        @meta = meta
      end

      def to_h
        payload = {
          "source" => @source,
          "bonus_type" => @bonus_type.to_s,
          "target" => @target.to_s,
          "value" => @value,
          "expires_at_game_hours" => @expires_at_game_hours
        }
        payload["meta"] = @meta if @meta.present?
        payload
      end
    end
  end
end
