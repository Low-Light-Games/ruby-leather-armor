# frozen_string_literal: true

# Seed spell definitions from the exported JSON file.
# Run: bin/rails runner db/seeds/spells.rb
#   or: bin/rails db:seed (if referenced from seeds.rb)

require "json"

json_path = Rails.root.join("db", "seeds", "spells.json")
spells = JSON.parse(File.read(json_path))

puts "Seeding #{spells.size} spell definitions..."

spells.each do |spell|
  SpellDefinition.find_or_initialize_by(id: spell["id"]).tap do |sd|
    sd.name               = spell["name"]
    sd.school             = spell["school"]
    sd.subschool          = spell["subschool"]
    sd.descriptors        = spell["descriptors"] || []
    sd.class_levels       = spell["classLevels"] || {}
    sd.components         = spell["components"] || []
    sd.material_component = spell["materialComponent"]
    sd.casting_time       = spell["castingTime"]
    sd.range              = spell["range"]
    sd.duration           = spell["duration"]
    sd.saving_throw       = spell["savingThrow"]
    sd.spell_resistance   = spell["spellResistance"] || false
    sd.effects            = spell["effects"] || []
    sd.summary            = spell["summary"]
    sd.save!
  end
end

puts "Done — #{SpellDefinition.count} spell definitions in the database."
