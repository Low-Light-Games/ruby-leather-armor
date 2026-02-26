# frozen_string_literal: true

# Seed item definitions from the exported JSON file.
# Run: bin/rails runner db/seeds/items.rb
#   or: bin/rails db:seed (if referenced from seeds.rb)

require "json"

json_path = Rails.root.join("db", "seeds", "items.json")
items = JSON.parse(File.read(json_path))

puts "Seeding #{items.size} item definitions..."

items.each do |item|
  ItemDefinition.find_or_initialize_by(id: item["id"]).tap do |id_rec|
    id_rec.name                = item["name"]
    id_rec.item_type           = item["itemType"]
    id_rec.category            = item["category"]
    id_rec.slot                = item["slot"] || "none"
    id_rec.weight              = item["weight"] || 0
    id_rec.cost_gp             = item["costGp"] || 0
    id_rec.armor_bonus         = item["armorBonus"] || 0
    id_rec.shield_bonus        = item["shieldBonus"] || 0
    id_rec.max_dex_bonus       = item["maxDexBonus"]
    id_rec.armor_check_penalty = item["armorCheckPenalty"] || 0
    id_rec.arcane_spell_failure = item["arcaneSpellFailure"] || 0
    id_rec.speed_30            = item["speed30"]
    id_rec.speed_20            = item["speed20"]
    id_rec.weapon_category     = item["weaponCategory"]
    id_rec.weapon_type         = item["weaponType"]
    id_rec.damage_dice         = item["damageDice"]
    id_rec.critical_range      = item["criticalRange"]
    id_rec.damage_type         = item["damageType"]
    id_rec.range_increment     = item["rangeIncrement"]
    id_rec.properties          = item["properties"] || {}
    id_rec.effects             = item["effects"] || []
    id_rec.summary             = item["summary"]
    id_rec.save!
  end
end

puts "Done — #{ItemDefinition.count} item definitions in the database."
