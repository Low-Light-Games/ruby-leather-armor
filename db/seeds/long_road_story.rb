# frozen_string_literal: true

# ── The Long Road ─────────────────────────────────────────────────────────────
# Two-location traversal story. Docks → Lighthouse Isle, separated by open
# water. Used by the swim_to_lighthouse e2e test to exercise:
#   - Skill-check generation for a deliberate Swim attempt
#   - Player position update after a successful traversal action
#
# StoryLocations have no x/y; coordinates are assigned per-adventure by
# Authoring::ExtractPremise during Adventures::Bootstrap. The premise below
# is written to nudge that step toward placing the two points roughly a
# kilometre apart over open water.

story = Story.find_or_initialize_by(title: "The Long Road")
story.preview = "A short crossing between the Sailspar Docks and the old Lighthouse Isle — interrupted by a kilometre of open water."
story.world_terrain = "plains"  # WORLD_TERRAINS = plains forest desert mountain swamp ice; "plains" is the closest neutral option for a coastal docks scene.
story.opening_message = <<~OPENING.strip
  Salt wind off the Sailspar Docks. Across the channel, less than a kilometre of grey water away, the old Lighthouse Isle sits low and weathered — its keeper hasn't lit the beacon in three nights. The harbourmaster will pay if someone reaches the isle and finds out why.
OPENING
story.premise = <<~PREMISE.strip
  Sailspar Docks and Lighthouse Isle are roughly one kilometre apart, separated by open water of the harbour channel. There are no bridges; travellers usually take a small skiff, but the boats are out for the night and the player must swim if they want to make the crossing themselves.

  Lighthouse Isle's keeper has gone silent. Three nights without the beacon. The premise is tightly scoped — there is no other land to explore, no inland route, only the dock-and-isle pairing and the kilometre of water between them.

  Travel between the two locations is by swimming or boat only. Treat the crossing as a single Swim skill check (DC 10 calm conditions, DC 15 rough). Failure means treading water at the dock; it does not mean drowning.
PREMISE
story.save!

puts "Created/updated story: #{story.title}"

locs = {
  "Sailspar Docks"   => { description: "Weathered wooden piers, rope and tar smell, salt-bleached planks. The skiffs are all out tonight.",                  starting: true },
  "Lighthouse Isle"  => { description: "A low rock outcrop a kilometre offshore. The lighthouse on its peak has been dark for three nights.",                starting: false },
}

count = 0
locs.each do |name, attrs|
  loc = story.story_locations.find_or_initialize_by(name: name)
  loc.update!(attrs)
  count += 1
end

puts "Seeded #{count} locations for '#{story.title}'"
