# frozen_string_literal: true

story = Story.find_or_initialize_by(title: "The Lake of Whispers")
story.preview = "A village has been having some people kidnapped at night, particularly from the houses nearer the lake."
story.premise = <<~PREMISE.strip
  The people vanishing from the village are being kidnapped and taken deep into the lake for the Aboleth to extract their memories and learn what is suppressing his power.

  The Kuo-Toa eat the people after the Aboleth abducts them, unbeknownst to the Aboleth, because they do so out of the water, where the Aboleth's power is suppresed by the statue of the Mad Mage.

  The statue of the Mad Mage is actually the self-petrified mage, who cast a spell upon himself to forever keep the Aboleth at bay, protecting the village he doomed.

  The Aboleth got there by being invoked by the mad mage 150 years ago. The Mage quickly realized he had doomed the village, and before thinking too much, he hastely petrified himself with a custom spell that made him petrified and forever a dormant protector of the village.
PREMISE
story.initial_context = <<~CONTEXT.strip
  The player is leaving his last camp, at 6 in the morning, just as the sun is coming up. Still 60 miles away from the village. The path ahead is a well worn dirt road with heavy foliage at the sides.
CONTEXT
story.initial_summary = <<~SUMMARY.strip
  The player doesn't know anything about the disappearances in the village except what the Quest Posting said:
  "People disappearing. Need adventurer help. Intelligent detectives or competent guards welcome"
SUMMARY
story.save!

puts "Created/updated story: #{story.title}"
