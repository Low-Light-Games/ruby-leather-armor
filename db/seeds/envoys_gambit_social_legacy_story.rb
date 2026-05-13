# frozen_string_literal: true

# Legacy social-focused version of Envoy's Gambit (restored from the old
# social_story seed lineage).

story = Story.find_or_initialize_by(title: "The Envoy's Gambit (Social Legacy)")
story.preview = "An envoy corners you in a quiet alcove of the inn — she has a proposition you haven't agreed to yet."
story.world_terrain = "plains"
story.opening_message = <<~OPENING.strip
  Seraphine Dusk sits across from you at a candlelit corner table in the Crossed Keys Inn. She folds her hands, watches you for a breath, and says, "I need a sealed ledger from a rival's vault before dawn. I can pay. Well." Around you, the common room pretends not to listen.
OPENING
story.premise = <<~PREMISE.strip
  Seraphine Dusk is a covert envoy for a minor noble house trying to survive a political purge.
  She has identified the player as someone unconnected enough to be useful and ruthless enough to
  be effective. She needs a specific sealed ledger retrieved from a rival's vault before the city
  guard raids it at dawn. She is charming, well-informed, and slightly desperate — though she
  would never let the desperation show. The player walked into the inn for a quiet drink and ended
  up in the middle of her pitch.
PREMISE
story.save!

puts "Created/updated story: #{story.title}"

inn = story.story_locations.find_or_initialize_by(name: "Crossed Keys Inn")
inn.update!(
  description: "A respectable mid-tier inn in the merchant quarter. Low candlelight, murmured conversations, a barkeep who minds his own business.",
  starting: true
)

puts "Seeded location for '#{story.title}'"

seraphine = story.story_npcs.find_or_initialize_by(name: "Seraphine Dusk")
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
