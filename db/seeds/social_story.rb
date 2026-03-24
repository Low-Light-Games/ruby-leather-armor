# frozen_string_literal: true

# ── Social Test Story ─────────────────────────────────────────────────────────
# Purpose: test the social / dialogue pipeline. The player begins mid-conversation
# with a StoryNpc — no travel, no combat preamble. The NPC is already speaking.

story = Story.find_or_initialize_by(title: "The Envoy's Gambit")
story.preview = "An envoy corners you in a quiet alcove of the inn — she has a proposition you haven't agreed to yet."
story.premise = <<~PREMISE.strip
  Seraphine Dusk is a covert envoy for a minor noble house trying to survive a political purge.
  She has identified the player as someone unconnected enough to be useful and ruthless enough to
  be effective. She needs a specific sealed ledger retrieved from a rival's vault before the city
  guard raids it at dawn. She is charming, well-informed, and slightly desperate — though she
  would never let the desperation show. The player walked into the inn for a quiet drink and ended
  up in the middle of her pitch.
PREMISE
story.initial_context = <<~CONTEXT.strip
  Seraphine Dusk is mid-sentence. The player is sitting across from her at a corner table in the
  Crossed Keys Inn, a half-empty tankard between them. She leans forward, voice low, and says:
  "—which is why I need someone the city register has never heard of. Someone like you. I can make
  it worth your while, considerably so, but I need your answer before the bell tower strikes eleven."
  She holds the player's gaze, fingers laced on the table, waiting.
CONTEXT
story.initial_summary = <<~SUMMARY.strip
  The player is already in conversation with Seraphine Dusk, a covert noble envoy, who has just
  made the tail end of a proposal. The player does not yet know the full details — only that
  Seraphine wants something retrieved tonight, before dawn, and that she is offering good money.
  The player has not agreed to anything.
SUMMARY
story.save!

puts "Created/updated story: #{story.title}"

# ── Location ───────────────────────────────────────────────────────────────────

inn = story.story_locations.find_or_initialize_by(name: "Crossed Keys Inn")
inn.update!(
  description: "A respectable mid-tier inn in the merchant quarter. Low candlelight, murmured conversations, a barkeep who minds his own business.",
  starting: true
)

puts "Seeded location for '#{story.title}'"

# ── StoryNpc — Seraphine Dusk ─────────────────────────────────────────────────

seraphine = story.story_npcs.find_or_initialize_by(name: "Seraphine Dusk", adventure_id: nil)
seraphine.update!(
  source: "manual",
  role: "quest_giver",
  attitude: "friendly",
  location: inn,
  description: <<~DESC.strip,
    Seraphine Dusk is a woman in her mid-thirties, dressed in understated but expensive travelling
    clothes. She has dark hair pinned back practically, sharp grey eyes that miss nothing, and the
    deliberate stillness of someone trained to give nothing away. She speaks quietly and precisely,
    never repeating herself. She is charming when it serves her and entirely ruthless when it does not.
  DESC
  knowledge: <<~KNOWLEDGE.strip,
    Seraphine knows the layout of the rival's townhouse and the location of the vault within it.
    She knows the city guard's raid schedule — dawn, under a magistrate's warrant. She knows the
    player's general reputation (enough to choose them) but not their full history. She does not
    know who tipped off the magistrate, which is a detail she finds troubling.
  KNOWLEDGE
  secret: false
)

puts "Seeded NPC '#{seraphine.name}' for '#{story.title}'"

# ── Encounter Table — minimal, social story should rarely fight ───────────────

table = story.encounter_tables.find_or_initialize_by(name: "The Envoy's Gambit — Urban Encounters")
table.update!(
  description: "Low-frequency urban encounters. Combat is rare; social and discovery events dominate.",
  check_frequency_hours: 6,
  encounter_chance: 10
)

urban_entries = [
  { title: "City Watch Patrol",    entry_type: "ai_prompt", weight: 3,
    description: "A city watch patrol passes close by. Describe their disposition — routine check, or are they looking for someone specific?" },
  { title: "Pickpocket Attempt",   entry_type: "fixed",     weight: 2,
    description: "A street thief tries their luck.",
    creature_manifest: [
      { "bestiary_entry_id" => "kobold", "count" => 1, "display_name" => "Street Thief" }
    ] },
  { title: "Overheard Rumour",     entry_type: "ai_prompt", weight: 3,
    description: "The player catches a fragment of conversation nearby — something about Seraphine, the noble house, or the city guard. Make it a partial clue that raises more questions than it answers." },
  { title: "Rival Tail",          entry_type: "ai_prompt", weight: 2,
    description: "Someone is following the player through the city streets. Describe who, how obvious they are, and whether they are hostile, curious, or just cautious." },
]

urban_entries.each do |attrs|
  entry = table.encounter_table_entries.find_or_initialize_by(title: attrs[:title])
  entry.update!(attrs)
end

puts "Seeded encounter table for '#{story.title}'"
