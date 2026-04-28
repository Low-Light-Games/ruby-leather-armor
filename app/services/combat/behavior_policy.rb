# frozen_string_literal: true

module Combat
  # Bestiary behavior policy (PR-F of the combat-determinism arc — see
  # docs/combat_redesign.md). Encodes how a creature picks an attack +
  # whether to approach when out of reach + when to flee. Applied
  # deterministically by Combat::NpcTurn so big battles don't spend an
  # AI call per NPC per round.
  #
  # v1 schema is intentionally tiny — most monsters need
  # "throw javelins until in melee range, then swing the axe" and not
  # much more. The policy schema is forward-compatible: unknown keys
  # are ignored, missing keys fall back to sensible defaults derived
  # from the creature's stat block.
  #
  # Schema (all keys optional):
  #
  #   {
  #     "preferred_attacks": [
  #       { "name": "javelin",   "min_range_squares": 4 },
  #       { "name": "longsword", "max_range_squares": 1 }
  #     ],
  #     "approach_when_out_of_reach": true,
  #     "morale": { "flee_at_hp_pct": 0.15 },
  #     "ability_triggers": []
  #   }
  class BehaviorPolicy
    DEFAULT_FLEE_HP_PCT = 0.0
    INFINITE = 1_000

    attr_reader :raw

    def initialize(raw)
      @raw = (raw || {}).deep_stringify_keys
    end

    # Returns the stored policy if any preferred_attacks are set;
    # otherwise derives a sensible default from the creature's
    # equipped_weapons so existing bestiary entries (and any
    # AI-generated creatures without an explicit policy) aren't inert.
    def self.for(creature)
      stored = new(creature.behavior_policy)
      return stored if stored.preferred_attacks.any?

      new(derive_from_creature(creature))
    end

    def self.derive_from_creature(creature)
      preferred = derive_attacks_from_weapons(creature)
      preferred = [{ 'name' => 'natural attack', 'max_range_squares' => 1 }] if preferred.empty?
      { 'preferred_attacks' => preferred, 'approach_when_out_of_reach' => true }
    end

    def self.derive_attacks_from_weapons(creature)
      Array(creature.equipped_weapons).filter_map do |w|
        next unless w.is_a?(Hash)

        name = w['name'] || w[:name]
        next unless name.to_s.match?(/\S/)

        ranged = (w['weapon_type'] || w[:weapon_type]).to_s == 'ranged'
        if ranged
          { 'name' => name.to_s, 'min_range_squares' => 2 }
        else
          { 'name' => name.to_s, 'max_range_squares' => 1 }
        end
      end
    end

    def preferred_attacks
      Array(@raw['preferred_attacks']).map { |a| AttackPreference.new((a || {}).deep_stringify_keys) }
    end

    def approach_when_out_of_reach?
      val = @raw['approach_when_out_of_reach']
      val.nil? || val == true
    end

    def flee_at_hp_pct
      morale = @raw['morale']
      return DEFAULT_FLEE_HP_PCT unless morale.is_a?(Hash)

      morale['flee_at_hp_pct'].to_f
    end

    def ability_triggers
      Array(@raw['ability_triggers'])
    end

    # Single attack preference: name + optional min/max engagement range
    # in squares. Either bound nil = unbounded.
    class AttackPreference
      attr_reader :name, :min_range_squares, :max_range_squares

      def initialize(raw)
        @name = raw['name'].to_s
        @min_range_squares = raw['min_range_squares']&.to_i
        @max_range_squares = raw['max_range_squares']&.to_i
      end

      def matches_distance?(distance_squares)
        return false if @min_range_squares && distance_squares < @min_range_squares

        return false if @max_range_squares && distance_squares > @max_range_squares

        true
      end

      def max_reach_squares
        @max_range_squares || BehaviorPolicy::INFINITE
      end
    end
  end
end
