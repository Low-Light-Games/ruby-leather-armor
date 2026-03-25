# frozen_string_literal: true

# ── Social Test Story ─────────────────────────────────────────────────────────
# Purpose: test the social / dialogue pipeline. The player begins mid-conversation
# with a StoryNpc — no travel, no combat preamble. The NPC is already speaking.

story = Story.find_or_initialize_by(title: "The Envoy's Gambit")
story.preview = "An envoy corners you in a quiet alcove of the inn — she has a proposition you haven't agreed to yet."
story.initial_contexts = {
  "traversal_context" => {
    "terrain"            => "urban",
    "weather"            => "clear night, cobblestones damp from earlier rain",
    "time_of_day"        => "evening",
    "nearby_npcs"        => [
      "Barkeep wiping down the counter",
      "Two merchants playing cards in the far corner"
    ],
    "points_of_interest" => [
      "Corner table where Seraphine is seated",
      "Inn entrance to the street",
      "Bar counter with a mostly empty common room"
    ]
  },
  "social_context" => {
    "scene"               => "The player sits across from Seraphine Dusk at a candlelit corner table in the Crossed Keys Inn. She has just finished the tail-end of her proposal and is watching the player closely, fingers laced on the table, waiting for an answer.",
    "npcs_present"        => [
      {
        "name"     => "Seraphine Dusk",
        "role"     => "covert noble envoy",
        "attitude" => "friendly",
        "notes"    => "Already mid-pitch — she needs a sealed ledger retrieved from a rival noble's vault before the city guard raids at dawn. She knows the vault layout and the guard schedule. She has offered considerable payment. Charming but carries a thread of desperation she is working hard to conceal."
      }
    ],
    "npcs_known"          => [],
    "conversation_state"  => "awaiting player's response to Seraphine's job proposal",
    "stakes"              => "Whether the player accepts a high-risk retrieval job — recover a sealed ledger from a rival's vault before the city guard raids it at dawn",
    "persuasion_progress" => "Seraphine has completed her pitch and named her price. The player has not yet responded."
  }
}
story.premise = <<~PREMISE.strip
  Seraphine Dusk is a covert envoy for a minor noble house trying to survive a political purge.
  She has identified the player as someone unconnected enough to be useful and ruthless enough to
  be effective. She needs a specific sealed ledger retrieved from a rival's vault before the city
  guard raids it at dawn. She is charming, well-informed, and slightly desperate — though she
  would never let the desperation show. The player walked into the inn for a quiet drink and ended
  up in the middle of her pitch.
PREMISE
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
