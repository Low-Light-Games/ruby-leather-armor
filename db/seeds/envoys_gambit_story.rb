# frozen_string_literal: true

# ── The Envoy's Gambit ────────────────────────────────────────────────────────
# Single-room conversational story used by the attack_envoy e2e test to
# exercise the post-roll combat-context-update path with a *named*
# antagonist. The named StoryNpc surfaces through lore retrieval into the
# AI's context, so when the player attacks the envoy the pipeline emits
# combatants with that exact name — which means RollRequest's combatants
# normalizer keeps the name (instead of mangling it to "name") and the
# downstream combat-context-update step deterministically reaches the
# "dropped creature_sheet_id for Lord Velkar Mhonn" guard in
# Steps::ContextUpdate#repair_participant_identity.

story = Story.find_or_initialize_by(title: "The Envoy's Gambit")
story.preview = "A diplomatic audience turns hostile. The envoy across the table knows more than they should — and is no longer pretending otherwise."
story.world_terrain = "plains"
story.opening_message = <<~OPENING.strip
  Lord Velkar Mhonn lets the silence stretch. He sets a sealed letter on the lacquered table between you — your seal, broken — and meets your eye for the first time since the audience began. "The Coalition will hear of this by sundown," he says, smiling thinly. "Unless, of course, we resolve it here." A guardsman tightens his grip on a pikeshaft by the door. Your hand has not moved from your knee.
OPENING
story.premise = <<~PREMISE.strip
  A diplomatic audience in Lord Velkar Mhonn's sealed chamber goes wrong the moment Velkar produces evidence the player's faction never authorised. Velkar is not bluffing — he intends to force a humiliating concession or, failing that, an "incident" he can explain to the Coalition on his own terms.

  The chamber is sealed. There is no retinue, no negotiation team, no way to escalate up a chain of command. Two guardsmen at the door answer to Velkar. The player is the entire diplomatic apparatus on their side of the table. Whatever happens here is what happens.

  Velkar himself is the only viable adversary in the scene. The guardsmen are scenery; the conversation is the substance. Combat with Velkar is dramatic, decisive, and irrecoverable for the diplomatic mission — but the player is permitted to choose it.
PREMISE
story.save!

puts "Created/updated story: #{story.title}"

locs = {
  "Velkar's Audience Chamber" => {
    description: "A long lacquered table, oil lamps low, the door sealed and guarded. Velkar sits at the far end; the player is opposite. There are no other ways out.",
    starting: true
  }
}

locs.each do |name, attrs|
  loc = story.story_locations.find_or_initialize_by(name: name)
  loc.update!(attrs)
end

audience_chamber = story.story_locations.find_by!(name: "Velkar's Audience Chamber")

velkar = story.story_npcs.find_or_initialize_by(name: "Lord Velkar Mhonn")
velkar.update!(
  source: "manual",
  role: "antagonist",
  attitude: "unfriendly",
  location: audience_chamber,
  description: "An older Coalition envoy in formal black-and-silver. Composed, watchful, faintly amused. His authority in this room is total.",
  knowledge: "Knows the contents of the broken-seal letter, knows it implicates the player's faction in a failed assassination attempt three years ago, and is fully prepared to leak it before nightfall unless the player concedes.",
  secret: false
)

puts "Seeded 1 location and 1 NPC for '#{story.title}'"
