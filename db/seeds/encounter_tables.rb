# frozen_string_literal: true

# Seed a global default encounter table and story-specific locations

# ---- Default Encounter Table (global, no story_id) ----

default_table = EncounterTable.find_or_initialize_by(story_id: nil, name: "Default Wilderness Encounters")
default_table.update!(
  description: "Generic wilderness encounters for stories without custom tables",
  check_frequency_hours: 4,
  encounter_chance: 15
)

entries = [
  { title: "Wolf Pack", entry_type: "fixed", weight: 3,
    description: "A pack of 3 wolves emerges from the undergrowth, snarling and circling. They are hungry and aggressive.",
    creature_manifest: [
      { "bestiary_entry_id" => "wolf", "count" => 3, "display_name" => "Wolf" }
    ] },
  { title: "Bandit Ambush", entry_type: "fixed", weight: 2,
    description: "Four bandits step out from behind rocks, weapons drawn. Their leader demands gold and valuables.",
    creature_manifest: [
      { "bestiary_entry_id" => "bandit", "count" => 3, "display_name" => "Bandit" },
      { "bestiary_entry_id" => "bandit", "count" => 1, "display_name" => "Bandit Leader" }
    ] },
  { title: "Traveling Merchant", entry_type: "ai_prompt", weight: 2,
    description: "A traveling merchant with unusual wares and a story to tell. Make the merchant memorable with a quirky personality and at least one intriguing item." },
  { title: "Unusual Weather", entry_type: "ai_prompt", weight: 1,
    description: "A sudden weather event that creates an obstacle or opportunity — a freak storm, dense fog, or an unseasonable chill." },
  { title: "Strange Discovery", entry_type: "ai_prompt", weight: 2,
    description: "The party stumbles upon something unexpected by the roadside — ruins, a body, a strange marker, or an abandoned camp." },
  { title: "Wild Animal", entry_type: "fixed", weight: 2,
    description: "A large wild animal blocks the path — a bear, boar, or territorial elk. It may be aggressive or simply defensive of its territory.",
    creature_manifest: [
      { "bestiary_entry_id" => "bear", "count" => 1, "display_name" => "Bear" }
    ] },
  { title: "Travelers in Need", entry_type: "ai_prompt", weight: 1,
    description: "A group of NPCs in some kind of trouble — a broken cart, an injury, or a dispute. The party can help, ignore, or take advantage." },
  { title: "Ancient Shrine", entry_type: "ai_prompt", weight: 1,
    description: "A weathered roadside shrine to a deity. It may offer a minor boon if respected, or carry a subtle curse if desecrated." },
]

entries.each do |attrs|
  entry = default_table.encounter_table_entries.find_or_initialize_by(title: attrs[:title])
  entry.update!(attrs)
end

puts "Seeded default encounter table: #{default_table.name} (#{default_table.encounter_table_entries.count} entries)"
