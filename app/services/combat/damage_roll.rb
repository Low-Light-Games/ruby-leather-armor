# frozen_string_literal: true

module Combat
  # Result of one rolled damage expression — total + damage type.
  # Combat::NpcAttackResolver passes one of these (or nil, when the
  # attack missed) through apply_damage_to and AttackSummary. Implements
  # `[]` so existing hash-style access keeps compiling.
  class DamageRoll
    attr_reader :total, :type

    # @param total [Integer]
    # @param type [String, nil]
    def initialize(total:, type:)
      @total = total
      @type = type
    end

    def to_h
      { total: total, type: type }
    end

    def [](key)
      to_h[key]
    end

    def fetch(key, *defaults)
      to_h.fetch(key, *defaults)
    end
  end
end
