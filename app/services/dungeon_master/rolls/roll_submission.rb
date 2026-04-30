# frozen_string_literal: true

module DungeonMaster
  module Rolls
    # Normalizes the player-roll payload submitted to
    # AdventureMessagesController#roll. Accepts both shapes the
    # frontend posts — a top-level :rolls array or a single flat
    # :roll_value/:roll_description/:resolution_method/:request_id —
    # and emits an Array<Hash> with the keys the rest of the pipeline
    # (PlayerRolls / RollResultsText) consumes. Owns the value-range
    # validation too so the controller doesn't restate it.
    class RollSubmission
      VALID_RANGE = -100..100

      class InvalidValueError < StandardError; end

      def initialize(params)
        @params = params
      end

      def to_a
        rolls = params_have_array? ? rolls_from_array : [single_roll_from_flat_params]
        rolls.each { |row| validate_value!(row[:roll_value]) }
        rolls
      end

      private

      def params_have_array?
        @params[:rolls].present?
      end

      def rolls_from_array
        Array(@params[:rolls]).map { |row| normalize_one(row) }
      end

      def single_roll_from_flat_params
        normalize_one(@params)
      end

      def normalize_one(row)
        {
          roll_value: row[:roll_value].to_i,
          roll_description: row[:roll_description]&.strip || 'unknown check',
          resolution_method: row[:resolution_method]&.strip,
          request_id: row[:request_id]&.strip.presence
        }
      end

      def validate_value!(value)
        return if VALID_RANGE.include?(value)

        raise InvalidValueError, "Roll value must be between #{VALID_RANGE.first} and #{VALID_RANGE.last}"
      end
    end
  end
end
