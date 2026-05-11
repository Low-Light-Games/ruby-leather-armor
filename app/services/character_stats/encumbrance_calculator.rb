# frozen_string_literal: true

module CharacterStats
  class EncumbranceCalculator
    include GameRules

    # @param items [Array<SheetItem|AdventureSheetItem|CreatureSheetItem>]
    # @param str_score [Integer]  final (post-racial, post-condition) STR score
    # @param size [String]        "Medium" or "Small"
    # @param coin_count [Integer] total coin count (50 coins = 1 lb)
    def initialize(items, str_score:, size:, coin_count: 0)
      @items      = items
      @str_score  = str_score
      @size       = size
      @coin_count = coin_count
    end

    # @param base_speed [Integer]  racial base speed in feet
    # @param equip [Hash]          result of CombatCalculator#equipment_bonuses
    # @return [Hash] with keys: :total_weight, :carry_capacity, :encumbrance,
    def compute(base_speed:, equip:)
      total_weight  = compute_total_weight
      carry_caps    = carry_capacity
      encumbrance   = compute_encumbrance_tier(total_weight, carry_caps)
      enc_limits    = encumbrance_limits(encumbrance)
      effective_spd = compute_effective_speed(base_speed, equip, encumbrance)

      {
        total_weight:    total_weight.round(2),
        carry_capacity:  { light: carry_caps[0], medium: carry_caps[1], heavy: carry_caps[2] },
        encumbrance:     encumbrance,
        enc_limits:      enc_limits,
        effective_speed: effective_spd,
      }
    end

    private

    def compute_total_weight
      item_weight = @items.sum do |si|
        item = si.item_definition
        next 0.0 unless item

        (item.weight || 0).to_f * (si.quantity || 1)
      end

      coin_weight = @coin_count.to_f / 50.0
      item_weight + coin_weight
    end

    def carry_capacity
      str = [@str_score, 0].max
      caps = if str < CARRY_CAPACITY.length
               CARRY_CAPACITY[str]
             else
               base = CARRY_CAPACITY[20]
               tens = ((str - 20) / 10.0).floor
               remainder = (str - 20) % 10
               rem_caps = remainder < 10 ? (CARRY_CAPACITY[20 + remainder] || CARRY_CAPACITY.last) : CARRY_CAPACITY.last
               multiplier = 4**tens
               rem_caps.map { |v| v * multiplier }
             end

      @size == "Small" ? caps.map { |v| (v * 0.75).floor } : caps
    end

    def compute_encumbrance_tier(total_weight, carry_caps)
      light_max, medium_max, heavy_max = carry_caps
      if total_weight <= light_max     then :light
      elsif total_weight <= medium_max then :medium
      elsif total_weight <= heavy_max  then :heavy
      else                                  :overloaded
      end
    end

    def encumbrance_limits(tier)
      case tier
      when :light     then { max_dex: nil, acp: 0,  run_multiplier: 4 }
      when :medium    then { max_dex: 3,   acp: -3, run_multiplier: 4 }
      when :heavy     then { max_dex: 1,   acp: -6, run_multiplier: 3 }
      when :overloaded then { max_dex: 0,  acp: -6, run_multiplier: 0 }
      else                 { max_dex: nil, acp: 0,  run_multiplier: 4 }
      end
    end

    def compute_effective_speed(base_speed, equip, encumbrance)
      armor_speed = base_speed >= 30 ? equip[:speed_30] : equip[:speed_20]

      enc_speed = if %i[medium heavy overloaded].include?(encumbrance)
                    base_speed >= 30 ? 20 : 15
                  else
                    base_speed
                  end

      speeds = [armor_speed, enc_speed].compact
      speeds.empty? ? base_speed : speeds.min
    end
  end
end
