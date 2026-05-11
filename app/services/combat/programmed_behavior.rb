# frozen_string_literal: true

module Combat
  class ProgrammedBehavior
    DEFAULT_FLEE_HP_PCT = 0.0
    INFINITE = 1_000

    attr_reader :raw

    def initialize(raw)
      @raw = (raw || {}).deep_stringify_keys
    end

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
        @max_range_squares || ProgrammedBehavior::INFINITE
      end
    end
  end
end
