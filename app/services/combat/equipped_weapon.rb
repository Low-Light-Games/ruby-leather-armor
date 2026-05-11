# frozen_string_literal: true

module Combat
  class EquippedWeapon
    DEFAULT_LABEL = 'weapon'

    attr_reader :label, :damage_dice, :damage_type

    # @param label [String]
    # @param damage_dice [String] e.g. '1d6', '1d8+1'
    # @param damage_type [String, nil] e.g. 'piercing'
    # @param ranged [Boolean]
    def initialize(label:, damage_dice:, damage_type:, ranged:)
      @label = label
      @damage_dice = damage_dice
      @damage_type = damage_type
      @ranged = ranged
    end

    def ranged?
      @ranged == true
    end

    def self.natural_attack(damage_dice)
      new(label: 'natural attack', damage_dice: damage_dice, damage_type: nil, ranged: false)
    end

    # @param raw [Hash] one entry from AdventureActorSheet#equipped_weapons
    def self.from_raw(raw)
      new(
        label: raw['name'].presence || raw[:name].presence || DEFAULT_LABEL,
        damage_dice: raw['damage_dice'] || raw[:damage_dice],
        damage_type: raw['damage_type'] || raw[:damage_type],
        ranged: (raw['weapon_type'] || raw[:weapon_type]).to_s == 'ranged'
      )
    end

    def to_h
      { label: label, damage: damage_dice, damage_type: damage_type, ranged: ranged? }
    end

    def [](key)
      to_h[key]
    end
  end
end
