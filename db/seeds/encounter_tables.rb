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
    description: "A pack of 3 wolves emerges from the undergrowth, snarling and circling. They are hungry and aggressive." },
  { title: "Bandit Ambush", entry_type: "fixed", weight: 2,
    description: "Four bandits step out from behind rocks, weapons drawn. Their leader demands gold and valuables." },
  { title: "Traveling Merchant", entry_type: "ai_prompt", weight: 2,
    description: "A traveling merchant with unusual wares and a story to tell. Make the merchant memorable with a quirky personality and at least one intriguing item." },
  { title: "Unusual Weather", entry_type: "ai_prompt", weight: 1,
    description: "A sudden weather event that creates an obstacle or opportunity — a freak storm, dense fog, or an unseasonable chill." },
  { title: "Strange Discovery", entry_type: "ai_prompt", weight: 2,
    description: "The party stumbles upon something unexpected by the roadside — ruins, a body, a strange marker, or an abandoned camp." },
  { title: "Wild Animal", entry_type: "fixed", weight: 2,
    description: "A large wild animal blocks the path — a bear, boar, or territorial elk. It may be aggressive or simply defensive of its territory." },
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

# ---- Locations for "The Lake of Whispers" ----

story = Story.find_by(title: "The Lake of Whispers")
if story
  locs = {
    "Millhaven" => {
      description: "A small fishing village on the southern shore of Lake Whisper. Wooden houses line a muddy main road leading to a dock.",
      starting: true
    },
    "Lake Shore" => {
      description: "The misty southern shore of Lake Whisper. Dark water laps at pebbled banks. Fishermen avoid this stretch after dusk.",
      starting: false
    },
    "Forest Path" => {
      description: "A narrow trail winding through dense woodland north of Millhaven. The canopy blocks most sunlight.",
      starting: false
    },
    "Abandoned Mine" => {
      description: "An old iron mine in the hills, long since exhausted. The entrance is partially collapsed but passable.",
      starting: false
    },
    "Sorcerer's Cove" => {
      description: "A hidden rocky inlet on the lake's eastern shore. Strange lights have been reported here at night.",
      starting: false
    }
  }

  location_records = {}
  locs.each do |name, attrs|
    loc = story.story_locations.find_or_initialize_by(name: name)
    loc.update!(attrs)
    location_records[name] = loc
  end

  connections = [
    ["Millhaven", "Lake Shore", 1.5, "trail"],
    ["Millhaven", "Forest Path", 2.0, "road"],
    ["Forest Path", "Abandoned Mine", 8.0, "forest"],
    ["Lake Shore", "Sorcerer's Cove", 5.0, "coast"],
    ["Forest Path", "Sorcerer's Cove", 12.0, "forest"],
  ]

  connections.each do |from_name, to_name, dist, terrain|
    from_loc = location_records[from_name]
    to_loc = location_records[to_name]
    conn = LocationConnection.find_or_initialize_by(from_location: from_loc, to_location: to_loc)
    conn.update!(distance_miles: dist, terrain_type: terrain)
  end

  puts "Seeded #{location_records.size} locations and #{connections.size} connections for '#{story.title}'"
else
  puts "Story 'The Lake of Whispers' not found — skipping location seed"
end
