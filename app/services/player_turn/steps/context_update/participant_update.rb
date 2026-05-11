# frozen_string_literal: true

module PlayerTurn
  module Steps
    module ContextUpdate
      # One participant delta from the `combat_context_update` AI step's
      # `participant_updates` array. The AI describes per-participant
      # deltas keyed on the integer `creature_sheet_id` already owned by
      # the canonical combat context; the canonical participant block
      # itself is owned by CombatGM mutations and is never rewritten here.
      #
      # `hp_delta`, `conditions_added`, and `conditions_removed` are all
      # individually optional. An entry with only `creature_sheet_id` is
      # a no-op kept around so log readers can see what the AI emitted.
      class ParticipantUpdate
        attr_reader :creature_sheet_id, :hp_delta, :conditions_added, :conditions_removed

        def self.parse(raw)
          return nil unless raw.is_a?(Hash)

          row = raw.deep_stringify_keys
          id  = Integer(row["creature_sheet_id"], exception: false)
          return nil unless id&.positive?

          new(
            creature_sheet_id:  id,
            hp_delta:           coerce_int(row["hp_delta"]),
            conditions_added:   Array(row["conditions_added"]).map { |c| c.to_s.strip }.reject(&:empty?),
            conditions_removed: Array(row["conditions_removed"]).map { |c| c.to_s.strip }.reject(&:empty?),
          )
        end

        def self.coerce_int(raw)
          return 0 if raw.nil? || raw == ""

          Integer(raw, exception: false) || 0
        end

        def initialize(creature_sheet_id:, hp_delta:, conditions_added:, conditions_removed:)
          @creature_sheet_id  = creature_sheet_id
          @hp_delta           = hp_delta.to_i
          @conditions_added   = conditions_added
          @conditions_removed = conditions_removed
        end

        def no_op?
          @hp_delta.zero? && @conditions_added.empty? && @conditions_removed.empty?
        end

        def to_h
          {
            creature_sheet_id:  @creature_sheet_id,
            hp_delta:           @hp_delta,
            conditions_added:   @conditions_added,
            conditions_removed: @conditions_removed,
          }
        end
      end
    end
  end
end
