# frozen_string_literal: true

module Adventures
  # Computes starting HP and remaining currency for a sheet entering an adventure.
  class StartingStats
    HIT_DIE_MAP = {
      "barbarian" => 12, "bard" => 8, "cleric" => 8, "druid" => 8,
      "fighter" => 10, "monk" => 8, "paladin" => 10, "ranger" => 10,
      "rogue" => 8, "sorcerer" => 6, "wizard" => 6
    }.freeze

    RACE_CON_MOD = {
      "dwarf" => 2, "elf" => -2, "gnome" => 2,
      "halfling" => 0, "human" => 0, "half_elf" => 0, "half_orc" => 0
    }.freeze

    def initialize(sheet)
      @sheet = sheet
    end

    # Max hit die + CON modifier at level 1,
    # then (hit_die/2 + 1 + CON mod) per additional level.
    def starting_hp
      hit_die  = HIT_DIE_MAP[@sheet.character_class] || 8
      con_mod  = constitution_modifier

      level_1_hp          = [hit_die + con_mod, 1].max
      additional_per_level = [(hit_die / 2) + 1 + con_mod, 1].max
      total_hp = level_1_hp + (@sheet.level - 1) * additional_per_level

      [total_hp, 1].max
    end

    # Remaining currency after subtracting item purchase costs.
    # Works in copper pieces to avoid floating-point drift.
    def remaining_currency
      currency = (@sheet.currency || {}).deep_dup
      total_cp = (currency["platinum"].to_i * 1000) +
                 (currency["gold"].to_i * 100) +
                 (currency["silver"].to_i * 10) +
                 currency["copper"].to_i

      items_cost_cp = @sheet.sheet_items.includes(:item_definition).sum do |si|
        cost_gp = si.item_definition&.cost_gp || 0
        (cost_gp * 100 * si.quantity).round
      end

      remaining_cp = [total_cp - items_cost_cp, 0].max

      pp, remaining_cp = remaining_cp.divmod(1000)
      gp, remaining_cp = remaining_cp.divmod(100)
      sp, cp = remaining_cp.divmod(10)

      { "platinum" => pp, "gold" => gp, "silver" => sp, "copper" => cp }
    end

    private

    def constitution_modifier
      racial_con   = RACE_CON_MOD[@sheet.race] || 0
      flexible_con = @sheet.racial_bonus_attribute == "constitution" ? 2 : 0
      final_con    = @sheet.constitution + racial_con + flexible_con
      ((final_con - 10).to_f / 2).floor
    end
  end
end
