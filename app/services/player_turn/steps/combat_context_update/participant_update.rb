# frozen_string_literal: true

module PlayerTurn
  module Steps
    module CombatContextUpdate
      class ParticipantUpdate
        attr_reader :actor_sheet_id, :hp_delta, :conditions_added, :conditions_removed

        def self.parse(raw)
          return nil unless raw.is_a?(Hash)

          row = raw.deep_stringify_keys
          id  = Integer(row["actor_sheet_id"], exception: false)
          return nil unless id&.positive?

          new(
            actor_sheet_id:  id,
            hp_delta:           coerce_int(row["hp_delta"]),
            conditions_added:   Array(row["conditions_added"]).map { |c| c.to_s.strip }.reject(&:empty?),
            conditions_removed: Array(row["conditions_removed"]).map { |c| c.to_s.strip }.reject(&:empty?),
          )
        end

        def self.coerce_int(raw)
          return 0 if raw.nil? || raw == ""

          Integer(raw, exception: false) || 0
        end

        def initialize(actor_sheet_id:, hp_delta:, conditions_added:, conditions_removed:)
          @actor_sheet_id  = actor_sheet_id
          @hp_delta           = hp_delta.to_i
          @conditions_added   = conditions_added
          @conditions_removed = conditions_removed
        end

        def no_op?
          @hp_delta.zero? && @conditions_added.empty? && @conditions_removed.empty?
        end

        def to_h
          {
            actor_sheet_id:  @actor_sheet_id,
            hp_delta:           @hp_delta,
            conditions_added:   @conditions_added,
            conditions_removed: @conditions_removed,
          }
        end
      end
    end
  end
end
