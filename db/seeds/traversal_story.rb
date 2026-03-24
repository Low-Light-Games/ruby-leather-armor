# frozen_string_literal: true

# ── Traversal Test Story ─────────────────────────────────────────────────────
# Purpose: exercise every terrain type and the traversal pipeline end-to-end.
# The story is deliberately barebones — premise exists only to frame travel.
# Locations are connected so each terrain type in LocationConnection::TERRAIN_TYPES
# appears at least once: road, trail, forest, mountain, swamp, desert, river,
# coast, urban, underground.

story = Story.find_or_initialize_by(title: "The Long Road")
story.preview = "A courier's route stretching from the sea cliffs to the cavern markets — every kind of road lies between."
story.premise = <<~PREMISE.strip
  A simple delivery job turned into an odyssey. The player must travel a full cross-country route,
  navigating coastal docks, river fords, deep forest, mountain passes, swamps, deserts, an
  underground trading post, and urban streets before reaching the final destination. No grand villain,
  no mystery — just the road and whatever it throws at the player.
PREMISE
story.initial_context = <<~CONTEXT.strip
  The player stands at the Coastal Docks at dawn, a sealed satchel slung over one shoulder.
  Gulls cry overhead and the smell of salt and fish hangs in the cool morning air.
  A battered signpost points inland: "Riverford Crossing — 12 mi". The road ahead begins as
  a cobbled street that quickly turns to packed dirt as it leaves the harbour behind.
CONTEXT
story.initial_summary = <<~SUMMARY.strip
  The player has accepted a courier contract: deliver a sealed satchel to the Underground Market
  at Cavern's Reach. The client paid half up front and warned that the package must arrive within
  seven days. The player knows nothing about the contents.
SUMMARY
story.save!

puts "Created/updated story: #{story.title}"

# ── Locations ────────────────────────────────────────────────────────────────

locs = {
  "Coastal Docks"          => { description: "A busy harbour town perched on chalk cliffs. Salt-encrusted warehouses line the waterfront.",          starting: true  },
  "Riverford Crossing"     => { description: "A wide, shallow ford across the Greymere River. A stone bridge was washed out last spring.",             starting: false },
  "Thornwall Village"      => { description: "A modest farming village at the edge of the Thornwall Forest, known for its amber mead.",               starting: false },
  "Deepwood Hollow"        => { description: "The dark heart of Thornwall Forest. The canopy is so thick that noon feels like dusk.",                 starting: false },
  "Cragger's Pass"         => { description: "A high mountain pass cut between two granite peaks. Wind is brutal and the footing treacherous.",       starting: false },
  "Bogmere Flats"          => { description: "An endless expanse of grey-green swamp. Twisted willows drip into black water.",                        starting: false },
  "Ashridge Wastes"        => { description: "A sun-blasted stretch of pale desert. The only shade is cast by bleached rock formations.",             starting: false },
  "Stonegate City"         => { description: "The region's largest walled city. Its streets are crowded and its alleys dangerous.",                   starting: false },
  "Cavern's Reach"         => { description: "An underground trading post carved into a vast natural cavern. Lanterns hang from stalactites.",        starting: false },
}

location_records = {}
locs.each do |name, attrs|
  loc = story.story_locations.find_or_initialize_by(name: name)
  loc.update!(attrs)
  location_records[name] = loc
end

# ── Connections — every TERRAIN_TYPE represented ─────────────────────────────
# terrain_type choices: road, trail, forest, mountain, swamp, desert, river, coast, urban, underground

connections = [
  # [from, to, distance_miles, terrain_type, description]
  ["Coastal Docks",      "Riverford Crossing", 12.0,  "coast",       "A coastal path hugging the cliff-edge, battered by sea spray."                ],
  ["Coastal Docks",      "Stonegate City",     25.0,  "road",        "The King's Road — wide, well-maintained, and heavily travelled."               ],
  ["Riverford Crossing", "Thornwall Village",  8.0,   "trail",       "A mud-churned trail used by loggers and farmers."                              ],
  ["Thornwall Village",  "Deepwood Hollow",    14.0,  "forest",      "The trail narrows and disappears into old-growth forest."                      ],
  ["Deepwood Hollow",    "Cragger's Pass",     22.0,  "mountain",    "A steep switchback climb through exposed rock and thin air."                   ],
  ["Deepwood Hollow",    "Bogmere Flats",      18.0,  "swamp",       "The forest floor gives way imperceptibly to marsh; there is no clear boundary."],
  ["Bogmere Flats",      "Ashridge Wastes",    30.0,  "desert",      "The swamp drains away and the land bakes into cracked pale clay."              ],
  ["Riverford Crossing", "Thornwall Village",   8.0,  "river",       "Wading the ford and following the river bank upstream."                        ],
  ["Stonegate City",     "Cavern's Reach",     10.0,  "urban",       "City streets give way to a descent into the mine-district tunnels."            ],
  ["Cragger's Pass",     "Cavern's Reach",     15.0,  "underground", "A known smuggler's route through natural caves beneath the pass."              ],
]

connections.each do |from_name, to_name, dist, terrain, desc|
  from_loc = location_records[from_name]
  to_loc   = location_records[to_name]
  conn = LocationConnection.find_or_initialize_by(from_location: from_loc, to_location: to_loc)
  conn.update!(distance_miles: dist, terrain_type: terrain, description: desc)
end

puts "Seeded #{location_records.size} locations and #{connections.size} connections for '#{story.title}'"

# ── Encounter Table (moderate, not the story's focus) ────────────────────────

table = story.encounter_tables.find_or_initialize_by(name: "The Long Road — Wilderness")
table.update!(
  description: "General travel encounters along the courier route.",
  check_frequency_hours: 4,
  encounter_chance: 20
)

road_entries = [
  { title: "Roadside Bandits",    entry_type: "fixed",    weight: 3, terrain_types: "road,trail",
    description: "A trio of desperate bandits step from the ditch demanding toll.",
    creature_manifest: [
      { "bestiary_entry_id" => "bandit", "count" => 3, "display_name" => "Bandit" }
    ] },
  { title: "Forest Predator",     entry_type: "fixed",    weight: 2, terrain_types: "forest",
    description: "A large predator shadows the player through the trees.",
    creature_manifest: [
      { "bestiary_entry_id" => "dire_wolf", "count" => 1, "display_name" => "Dire Wolf" }
    ] },
  { title: "Mountain Hazard",     entry_type: "ai_prompt", weight: 2, terrain_types: "mountain",
    description: "A rockslide, sudden storm, or patch of treacherous ice blocks the pass. Describe the environmental danger and the skill check required to push through." },
  { title: "Swamp Ambush",        entry_type: "fixed",    weight: 2, terrain_types: "swamp",
    description: "Creatures lurch from the murky water.",
    creature_manifest: [
      { "bestiary_entry_id" => "zombie", "count" => 4, "display_name" => "Bog Zombie" }
    ] },
  { title: "Desert Wanderer",     entry_type: "ai_prompt", weight: 1, terrain_types: "desert",
    description: "A lone figure in desert wrappings crosses the player's path. They may be a guide, a mirage, or something more sinister." },
  { title: "River Crossing Toll", entry_type: "ai_prompt", weight: 2, terrain_types: "river,coast",
    description: "A ferryman demands an unusual price for passage — not gold but a favour, a secret, or a service." },
  { title: "Underground Ambush",  entry_type: "fixed",    weight: 3, terrain_types: "underground",
    description: "Kobolds have rigged the tunnel with crude traps and wait in the dark.",
    creature_manifest: [
      { "bestiary_entry_id" => "kobold", "count" => 5, "display_name" => "Kobold Trapper" }
    ] },
  { title: "Strange Discovery",   entry_type: "ai_prompt", weight: 2,
    description: "Something unexpected sits beside the route — ruins, an abandoned cart, a buried chest partially exposed by rain." },
]

road_entries.each do |attrs|
  entry = table.encounter_table_entries.find_or_initialize_by(title: attrs[:title])
  entry.update!(attrs)
end

puts "Seeded encounter table for '#{story.title}'"
