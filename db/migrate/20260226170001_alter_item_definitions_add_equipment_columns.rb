# frozen_string_literal: true

class AlterItemDefinitionsAddEquipmentColumns < ActiveRecord::Migration[7.1]
  def change
    # Slot (body slot for equipping)
    add_column :item_definitions, :slot, :string, null: false, default: "none"

    # Rename cost → cost_gp and widen to decimal for fractional gold
    rename_column :item_definitions, :cost, :cost_gp
    change_column :item_definitions, :cost_gp, :decimal, precision: 10, scale: 2, null: false, default: 0

    # Widen weight precision
    change_column :item_definitions, :weight, :decimal, precision: 8, scale: 2, null: false, default: 0

    # Rename ac_bonus → armor_bonus for clarity
    rename_column :item_definitions, :ac_bonus, :armor_bonus

    # Add shield bonus (separate from armor)
    add_column :item_definitions, :shield_bonus, :integer, null: false, default: 0

    # Arcane spell failure percentage
    add_column :item_definitions, :arcane_spell_failure, :integer, null: false, default: 0

    # ── Weapon stats (full scaffolding) ──
    add_column :item_definitions, :weapon_category, :string   # simple, martial, exotic
    add_column :item_definitions, :weapon_type,     :string   # melee, ranged
    add_column :item_definitions, :damage_dice,     :string   # "1d8", "2d6"
    add_column :item_definitions, :critical_range,  :string   # "19-20/x2", "x3"
    add_column :item_definitions, :damage_type,     :string   # slashing, piercing, bludgeoning
    add_column :item_definitions, :range_increment, :integer  # feet, for ranged/thrown

    # Effects JSONB (same schema as feat effects)
    add_column :item_definitions, :effects, :jsonb, null: false, default: []

    add_index :item_definitions, :slot, name: "index_item_definitions_on_slot"
  end
end
