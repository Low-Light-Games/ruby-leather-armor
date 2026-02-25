# frozen_string_literal: true

# Seed feat definitions from the exported JSON file.
# Run: bin/rails runner db/seeds/feats.rb
#   or: bin/rails db:seed (if referenced from seeds.rb)

require "json"

json_path = Rails.root.join("db", "seeds", "feats.json")
feats = JSON.parse(File.read(json_path))

puts "Seeding #{feats.size} feat definitions..."

feats.each do |feat|
  FeatDefinition.find_or_initialize_by(id: feat["id"]).tap do |fd|
    fd.name          = feat["name"]
    fd.category      = feat["category"]
    fd.summary       = feat["summary"]
    fd.repeatable    = feat["repeatable"] || false
    fd.choice_type   = feat["choiceType"]
    fd.prerequisites = feat["prerequisites"] || []
    fd.effects       = feat["effects"] || []
    fd.save!
  end
end

puts "Done — #{FeatDefinition.count} feat definitions in the database."
