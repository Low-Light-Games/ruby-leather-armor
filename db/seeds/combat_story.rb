# frozen_string_literal: true

# ── Combat Test Story ─────────────────────────────────────────────────────────
# Purpose: stress-test the combat pipeline. Encounter chance is extreme — the
# player will fight constantly. Locations are minimal; the journey is short so
# combat is the dominant activity, not traversal.

story = Story.find_or_initialize_by(title: "The Bloodfield March")
story.preview = "A desperate push through war-torn land overrun with enemies. Every mile is a fight."
story.world_terrain = "plains"
story.opening_message = <<~OPENING.strip
  Smoke from burning tents drifts across the road. The mercenary company you marched with is dead — bodies scattered in the mud, supply wagons overturned. To the north, the silhouette of Garrison Keep rises above the field. Behind you, an orc patrol has spotted the smoke. There is no path back.
OPENING
story.premise = <<~PREMISE.strip
  A mercenary company was wiped out and the player is the only survivor. Surrounded by roving warbands,
  undead stirred by the battle's carnage, and opportunistic monsters, the player must fight their way
  from the ruined Forward Camp to the relative safety of Garrison Keep. There are no allies, no
  diplomacy, no puzzles — only the next enemy.
PREMISE
story.save!

puts "Created/updated story: #{story.title}"

# ── Locations ─────────────────────────────────────────────────────────────────

locs = {
  "Ruined Forward Camp" => { description: "A smouldering mercenary camp. Overturned wagons, burning tents, and scattered dead.", starting: true },
  "The Bloodfield"      => { description: "An open stretch of battle-scarred farmland, churned to mud and soaked in blood.",    starting: false },
  "Garrison Keep"       => { description: "A squat stone fortification. Its gate is sealed but light shows from the battlements.", starting: false },
}

location_records = {}
locs.each do |name, attrs|
  loc = story.story_locations.find_or_initialize_by(name: name)
  loc.update!(attrs)
  location_records[name] = loc
end

puts "Seeded #{location_records.size} locations for '#{story.title}'"

# ── Encounter Table — extremely aggressive ────────────────────────────────────
# check_frequency_hours: 1 → checked every in-game hour
# encounter_chance: 85 → 85 % chance of a fight each check

table = story.encounter_tables.find_or_initialize_by(name: "The Bloodfield — Combat Gauntlet")
table.update!(
  description: "High-density combat encounters for pipeline stress testing. Fights happen constantly.",
  check_frequency_hours: 1,
  encounter_chance: 85
)

combat_entries = [
  { title: "Warband Patrol",         entry_type: "fixed",    weight: 4,
    description: "A four-person enemy patrol spots the player and charges.",
    creature_manifest: [
      { "bestiary_entry_id" => "orc",  "count" => 3, "display_name" => "Orc Soldier"  },
      { "bestiary_entry_id" => "orc",  "count" => 1, "display_name" => "Orc Sergeant" }
    ] },
  { title: "Goblin Skirmishers",     entry_type: "fixed",    weight: 4,
    description: "A squad of goblins descends from a ruined farmhouse rooftop.",
    creature_manifest: [
      { "bestiary_entry_id" => "goblin", "count" => 6, "display_name" => "Goblin Skirmisher" }
    ] },
  { title: "Risen Dead",             entry_type: "fixed",    weight: 3,
    description: "Battlefield carnage has stirred the fallen. A pack of zombies lurches toward the player.",
    creature_manifest: [
      { "bestiary_entry_id" => "zombie",   "count" => 3, "display_name" => "Battlefield Zombie" },
      { "bestiary_entry_id" => "skeleton", "count" => 2, "display_name" => "Risen Skeleton"     }
    ] },
  { title: "Dire Wolf Pack",         entry_type: "fixed",    weight: 3,
    description: "Drawn by the smell of blood, a pack of dire wolves closes in.",
    creature_manifest: [
      { "bestiary_entry_id" => "dire_wolf", "count" => 2, "display_name" => "Dire Wolf" },
      { "bestiary_entry_id" => "wolf",      "count" => 3, "display_name" => "Wolf"      }
    ] },
  { title: "Orc Warboss Vanguard",   entry_type: "fixed",    weight: 2,
    description: "The vanguard of a larger warband, scouting ahead — dangerous and well-armed.",
    creature_manifest: [
      { "bestiary_entry_id" => "orc",  "count" => 2, "display_name" => "Orc Elite"   },
      { "bestiary_entry_id" => "orc",  "count" => 1, "display_name" => "Orc Warboss" }
    ] },
  { title: "Skeleton Archers",       entry_type: "fixed",    weight: 2,
    description: "A line of skeletal archers holds a choke point, loosing arrows at anything that moves.",
    creature_manifest: [
      { "bestiary_entry_id" => "skeleton", "count" => 5, "display_name" => "Skeleton Archer" }
    ] },
]

combat_entries.each do |attrs|
  entry = table.encounter_table_entries.find_or_initialize_by(title: attrs[:title])
  entry.update!(attrs)
end

table.encounter_table_entries.where(entry_type: "ai_prompt").destroy_all

puts "Seeded encounter table for '#{story.title}'"
