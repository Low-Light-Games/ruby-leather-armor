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

# ---- Locations for "The Lake of Whispers" ----

story = Story.find_by(title: "The Lake of Whispers")
if story
  locs = {
    "Starting Encampment" => {
      description: "A random encampment made by the player before the start of the story",
      starting: true
    },
    "Village" => {
      description: "The Village that has been having the disappearances.",
      starting: false
    },
    "Closest Big City" => {
      description: "The closest big city the player may go to for resources he cannot get in the village.",
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
    ["Starting Encampment", "Village", 60.0, "trail"],
    ["Closest Big City", "Village", 180.0, "road"],
  ]

  connections.each do |from_name, to_name, dist, terrain|
    from_loc = location_records[from_name]
    to_loc = location_records[to_name]
    conn = LocationConnection.find_or_initialize_by(from_location: from_loc, to_location: to_loc)
    conn.update!(distance_miles: dist, terrain_type: terrain)
  end

  puts "Seeded #{location_records.size} locations and #{connections.size} connections for '#{story.title}'"

  # ---- NPCs ----

  npc_defs = [
    {
      name: "Priest",
      role: "informant",
      location_key: "Village",
      description: "The Priest is the one that placed Quest Postings around. He believes the disappearances have to do with a secret cult brewing in the village.",
      knowledge: "That the lake is to be avoided due to great evil within, but he has that information as folk knowledge.",
      attitude: "friendly",
      secret: false,
    },
    {
      name: "Escapee Abductee",
      role: "informant",
      location_key: "Village",
      description: "This villager was almost abducted and had his memories read, but he escaped the Kuo-Toa before they ate him. His mind is shattered, but he can let the player know about the kuo-toa.",
      knowledge: "",
      attitude: "indifferent",
      secret: true,
    },
    {
      name: "Bartender",
      role: "informant",
      location_key: "Village",
      description: "The Bartender can clue the player to the rumoured Escapee Abductee.",
      knowledge: "Knows of the Escapee Abductee",
      attitude: "indifferent",
      secret: false,
    },
    {
      name: "Young Mage Apprentice",
      role: "informant",
      location_key: "Village",
      description: "This NPC can be seen only at night, near the Mage Statue. He studies the local history of the village and he believes the Mage statue is a secret to more power.",
      knowledge: "He knows the mage statue is magic and not just decoration.",
      attitude: "indifferent",
      secret: false,
    },
    {
      name: "The Aboleth",
      role: "antagonist",
      location_key: "Village",
      description: "The Aboleth is deep inside the lake, it controls the fish people and cannot reach minds outside of the water.",
      knowledge: "",
      attitude: "indifferent",
      secret: true,
    },
  ]

  npc_records = {}
  npc_defs.each do |attrs|
    location_key = attrs.delete(:location_key)
    npc = story.story_npcs.find_or_initialize_by(name: attrs[:name], adventure_id: nil)
    npc.assign_attributes(attrs.merge(source: "manual", location: location_key ? location_records[location_key] : nil))
    npc.save!
    npc_records[npc.name] = npc
  end

  puts "Seeded #{npc_records.size} NPCs for '#{story.title}'"

  # ---- Clues ----

  clue_defs = [
    {
      title: "The Lake Is Avoided",
      description: "Even though the village setup is clearly that of a fishing village, no villager goes close to the lake.",
      discovery_method: "exploration",
      difficulty: "easy",
      location_key: "Village",
      npc_name: "Priest",
      prerequisite_titles: [],
      reveals_secret: "This lets the player know there is something wrong with the lake and possibly deduce the lake is dangerous. A hard check may enable the player to deduce the possible water-based threats.",
    },
    {
      title: "The Mage Statue Is Magical",
      description: "The Mage Statue is magical, and it seems to be warding off something.",
      discovery_method: "exploration",
      difficulty: "easy",
      location_key: "Village",
      npc_name: "Young Mage Apprentice",
      prerequisite_titles: [],
      reveals_secret: "This lets the player know further interaction with the statue may help",
    },
    {
      title: "There Is An Aboleth Controlling The Fish People (Abductee)",
      description: "The escapee abductee can reveal his meeting with the Aboleth if his mind is read in a conscious effort to remember the night he was abducted. The checks for such reveal are exceedingly hard though, he will most likely reveal just the fish people.",
      discovery_method: "exploration",
      difficulty: "hard",
      location_key: "Village",
      npc_name: "Escapee Abductee",
      prerequisite_titles: [],
      reveals_secret: "The main antagonist behind the disappearances is the Aboleth.",
    },
    {
      title: "There Is An Aboleth Controlling The Fish People (Kuo-Toa)",
      description: "If a Kuo-Toa is captured and interrogated by someone that can understand it or has \"Speak With Dead\" cast on it, it may reveal the Aboleth.",
      discovery_method: "exploration",
      difficulty: "moderate",
      location_key: nil,
      npc_name: nil,
      prerequisite_titles: [],
      reveals_secret: "The main antagonist behind the disappearances is the Aboleth.",
    },
    {
      title: "There Are Fish People Kidnapping The Villagers",
      description: "Kuo-toa are the ones culpable for the missing villagers",
      discovery_method: "exploration",
      difficulty: "moderate",
      location_key: "Village",
      npc_name: "Escapee Abductee",
      prerequisite_titles: [],
      reveals_secret: "There Are Fish People Kidnapping The Villagers",
    },
    {
      title: "Someone was abducted but escaped",
      description: "There is a survivor of an attempted kidnapping",
      discovery_method: "exploration",
      difficulty: "easy",
      location_key: nil,
      npc_name: "Bartender",
      prerequisite_titles: [],
      reveals_secret: "The location and nature of the Escapee Abductee",
    },
  ]

  clue_records = {}
  clue_defs.each do |attrs|
    location_key = attrs.delete(:location_key)
    npc_name = attrs.delete(:npc_name)
    prerequisite_titles = attrs.delete(:prerequisite_titles)

    clue = story.story_clues.find_or_initialize_by(title: attrs[:title], adventure_id: nil)
    clue.assign_attributes(
      attrs.merge(
        source: "manual",
        location: location_key ? location_records[location_key] : nil,
        npc: npc_name ? npc_records[npc_name] : nil,
        prerequisite_clue_ids: prerequisite_titles.map { |t| clue_records[t]&.id }.compact,
      )
    )
    clue.save!
    clue_records[clue.title] = clue
  end

  puts "Seeded #{clue_records.size} clues for '#{story.title}'"

  # ---- Milestones ----

  milestone_defs = [
    {
      title: "Discovered the Fish People Are Behind The Disappearances",
      description: "The Player discovered the fish people are the ones kidnapping the people.",
      trigger_titles: ["There Are Fish People Kidnapping The Villagers"],
      consequence: "",
    },
    {
      title: "Discovered The Aboleth Is Behind The Disappearances",
      description: "The Player discovered the Aboleth is behind the kidnappings.",
      trigger_titles: ["There Is An Aboleth Controlling The Fish People (Abductee)", "There Is An Aboleth Controlling The Fish People (Kuo-Toa)"],
      consequence: "",
    },
  ]

  milestone_defs.each do |attrs|
    trigger_titles = attrs.delete(:trigger_titles)
    ms = story.story_milestones.find_or_initialize_by(title: attrs[:title])
    ms.assign_attributes(
      attrs.merge(
        source: "manual",
        trigger_clue_ids: trigger_titles.map { |t| clue_records[t]&.id }.compact,
      )
    )
    ms.save!
  end

  puts "Seeded #{milestone_defs.size} milestones for '#{story.title}'"
else
  puts "Story 'The Lake of Whispers' not found — skipping location seed"
end
