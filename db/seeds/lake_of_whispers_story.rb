# frozen_string_literal: true

story = Story.find_or_initialize_by(title: "The Lake of Whispers")
story.preview = "A village has been having some people kidnapped at night, particularly from the houses nearer the lake."
story.premise = <<~PREMISE.strip
  The people vanishing from the village are being kidnapped and taken deep into the lake for the Aboleth to extract their memories and learn what is suppressing his power.

  The Kuo-Toa eat the people after the Aboleth abducts them, unbeknownst to the Aboleth, because they do so out of the water, where the Aboleth's power is suppresed by the statue of the Mad Mage.

  The statue of the Mad Mage is actually the self-petrified mage, who cast a spell upon himself to forever keep the Aboleth at bay, protecting the village he doomed.

  The Aboleth got there by being invoked by the mad mage 150 years ago. The Mage quickly realized he had doomed the village, and before thinking too much, he hastely petrified himself with a custom spell that made him petrified and forever a dormant protector of the village.
PREMISE
story.opening_message = <<~OPENING.strip
  A quest posting flutters on the village notice-board: "People disappearing. Need adventurer help. Intelligent detectives or competent guards welcome." The lake stretches dark beyond the rooftops, and the houses nearest its shore have been hit hardest. You are the first adventurer to answer.
OPENING
story.world_terrain = "swamp"
story.save!

puts "Created/updated story: #{story.title}"
