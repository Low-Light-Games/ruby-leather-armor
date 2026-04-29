# frozen_string_literal: true

module Combat
  # Result hashes Combat::NpcTurn used to inline. Each event reports one
  # creature's outcome for the round (an attack, an approach move, a
  # skipped turn, a flee), serialized to the same hash shape the HUD
  # already consumes (so the wire format is unchanged).
  module NpcTurnEvent
    KIND_ATTACK = 'npc_attack'
    KIND_MOVE   = 'npc_move'
    KIND_SKIP   = 'npc_skip'
    KIND_FLEE   = 'npc_flee'

    # @param creature [CreatureSheet]
    # @param attack_pref [Combat::ProgrammedBehavior::AttackPreference]
    # @param outcome [Combat::NpcAttackOutcome]
    class Attack
      attr_reader :creature, :attack_pref, :outcome

      def initialize(creature:, attack_pref:, outcome:)
        @creature = creature
        @attack_pref = attack_pref
        @outcome = outcome
      end

      def to_h
        {
          kind: KIND_ATTACK,
          creature_id: creature.id,
          creature_name: creature.name,
          attack_label: attack_pref.name,
          outcome: outcome.to_h
        }
      end
    end

    # @param creature [CreatureSheet]
    # @param from [Hash{x: Integer, y: Integer}]
    # @param to [Hash{x: Integer, y: Integer}]
    class Move
      attr_reader :creature, :from, :to

      def initialize(creature:, from:, to:)
        @creature = creature
        @from = from
        @to = to
      end

      def to_h
        {
          kind: KIND_MOVE,
          creature_id: creature.id,
          creature_name: creature.name,
          from: from,
          to: to,
          message: "#{creature.name} closes to (#{to[:x]}, #{to[:y]})."
        }
      end
    end

    # @param creature [CreatureSheet]
    # @param reason [String]
    class Skip
      attr_reader :creature, :reason

      def initialize(creature:, reason:)
        @creature = creature
        @reason = reason
      end

      def to_h
        {
          kind: KIND_SKIP,
          creature_id: creature.id,
          creature_name: creature.name,
          message: "#{creature.name} holds — #{reason}."
        }
      end
    end

    # @param creature [CreatureSheet]
    # @param from [Hash{x: Integer, y: Integer}]
    # @param to [Hash{x: Integer, y: Integer}]
    class Flee
      attr_reader :creature, :from, :to

      def initialize(creature:, from:, to:)
        @creature = creature
        @from = from
        @to = to
      end

      def to_h
        {
          kind: KIND_FLEE,
          creature_id: creature.id,
          creature_name: creature.name,
          from: from,
          to: to,
          message: "#{creature.name} flees to (#{to[:x]}, #{to[:y]})."
        }
      end
    end
  end
end
