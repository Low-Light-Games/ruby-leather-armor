# frozen_string_literal: true

# ── Combat Test Story ─────────────────────────────────────────────────────────
# Purpose: stress-test the combat pipeline. Encounter chance is extreme — the
# player will fight constantly. Locations are minimal; the journey is short so
# combat is the dominant activity, not traversal.

story = Story.find_or_initialize_by(title: "The Bloodfield March")
story.preview = "A desperate push through war-torn land overrun with enemies. Every mile is a fight."
story.initial_contexts = {
  "traversal_context" => {
    "terrain"            => "road",
    "weather"            => "overcast morning, acrid smoke drifting from burning tents",
    "time_of_day"        => "morning",
    "nearby_npcs"        => [
      "Distant orc patrol visible across the open field",
      "Two goblin scouts picking through mercenary corpses to the east"
    ],
    "points_of_interest" => [
      "Overturned supply wagon (provides cover)",
      "Bodies of fallen mercenaries scattered across the mud",
      "Smouldering tent remnants",
      "Garrison Keep silhouette visible to the north"
    ]
  }
}
story.premise = <<~PREMISE.strip
  A mercenary company was wiped out and the player is the only survivor. Surrounded by roving warbands,
  undead stirred by the battle's carnage, and opportunistic monsters, the player must fight their way
  from the ruined Forward Camp to the relative safety of Garrison Keep. There are no allies, no
  diplomacy, no puzzles — only the next enemy.
PREMISE
story.initial_summary = <<~SUMMARY.strip
  The player must cross from the Forward Camp to Garrison Keep. Enemy patrols cover every route.
  The player has no information about what awaits at the Keep — only that it is the nearest
  defensible position. Survival is the only objective.
SUMMARY
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

connections = [
  ["Ruined Forward Camp", "The Bloodfield", 2.0,  "road",   "An exposed road across open ground — no cover."],
  ["The Bloodfield",      "Garrison Keep",  2.0,  "road",   "The final stretch, uphill, toward the Keep's sealed gate."],
]

connections.each do |from_name, to_name, dist, terrain, desc|
  from_loc = location_records[from_name]
  to_loc   = location_records[to_name]
  conn = LocationConnection.find_or_initialize_by(from_location: from_loc, to_location: to_loc)
  conn.update!(distance_miles: dist, terrain_type: terrain, description: desc)
end

puts "Seeded #{location_records.size} locations and #{connections.size} connections for '#{story.title}'"

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
  { title: "Ambush from the Ruins",  entry_type: "ai_prompt", weight: 2,
    description: "Enemies have set a clever ambush using the battlefield terrain — describe the setup, who they are, how many, and what tactical advantage they press." },
  { title: "Desperate Skirmish",     entry_type: "ai_prompt", weight: 1,
    description: "Two enemy factions are fighting each other and the player blunders into the middle. Describe both sides, their disposition toward the player, and the chaotic battlefield." },
]

combat_entries.each do |attrs|
  entry = table.encounter_table_entries.find_or_initialize_by(title: attrs[:title])
  entry.update!(attrs)
end

puts "Seeded encounter table for '#{story.title}'"
