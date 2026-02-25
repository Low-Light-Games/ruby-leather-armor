# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require 'bcrypt'

# Create admin user
admin = User.find_or_initialize_by(email: 'admin@example.com')
admin.admin = true
admin.password_digest = BCrypt::Password.create('admin123')
admin.save!

# Create a regular test user
test_user = User.find_or_initialize_by(email: 'test@example.com')
test_user.admin = false
test_user.password_digest = BCrypt::Password.create('test123')
test_user.save!

puts "Created/updated admin user: #{admin.email} (password: admin123)"
puts "Created/updated test user: #{test_user.email} (password: test123)"

# Create stories
aboleth_story = Story.find_or_initialize_by(title: 'The Lake of Whispers')
aboleth_story.preview = 'A village has been having some people kidnapped at night, particularly from the houses nearer the lake.'
aboleth_story.premise = <<~PREMISE.strip
  The actual story has to do with an Aboleth that was evoked by a mad sorcerer who has since created a spell to kill himself, trap his essence in a statue and keeps the Aboleth at bay. But the aboleth has been using kuo-toa to kidnap people and see if he can eventually get to the village priest who may be able to suppress or destroy the statue and make the Aboleth free. The Aboleth does not know exactly what is supressing his powers, but he does know he is somewhat free inside the lake.
PREMISE
aboleth_story.save!

# Create story states for the Aboleth story
aboleth_story.story_states.destroy_all # Clear any existing states

aboleth_story.story_states.create!(
  description: 'The hero is on his way to the village.'
)

aboleth_story.story_states.create!(
  description: 'The hero is meeting the village people and talking and asking around about the dissapearences.'
)

aboleth_story.story_states.create!(
  description: 'The hero patrols at night hoping to get a glimpse of something suspicious.'
)

puts "Created/updated story: #{aboleth_story.title} with #{aboleth_story.story_states.count} stages"

# Seed feat and spell definitions
load Rails.root.join("db", "seeds", "feats.rb")
load Rails.root.join("db", "seeds", "spells.rb")
