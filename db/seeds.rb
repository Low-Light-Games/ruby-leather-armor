# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Reference / catalog data — needed in all environments
load Rails.root.join("db", "seeds", "feats.rb")
load Rails.root.join("db", "seeds", "spells.rb")
load Rails.root.join("db", "seeds", "items.rb")
load Rails.root.join("db", "seeds", "bestiary.rb")

# Story content — must run before encounter_tables, which depends on stories existing
load Rails.root.join("db", "seeds", "traversal_story.rb")
load Rails.root.join("db", "seeds", "combat_story.rb")
load Rails.root.join("db", "seeds", "social_story.rb")
load Rails.root.join("db", "seeds", "encounter_tables.rb")

# Only bootstrap local development — production admin accounts should be
# created through a secure out-of-band process.
if Rails.env.development? || Rails.env.staging? || Rails.env.playwright?
  # Skip the character-onboarding wizard for seeded accounts so Playwright (and
  # local smoke tests) land on /adventures/new with story/sheet picks. New users
  # still get onboarding_state "new" from the schema default.
  admin = User.find_or_initialize_by(email: 'admin@example.com')
  admin.admin = true
  admin.password = 'admin123'
  admin.onboarding_state = "in_progress"
  admin.save!

  test_user = User.find_or_initialize_by(email: 'test@example.com')
  test_user.admin = false
  test_user.password = 'test123'
  test_user.onboarding_state = "in_progress"
  test_user.save!

  puts "Created/updated admin user: #{admin.email} (password: admin123)"
  puts "Created/updated test user: #{test_user.email} (password: test123)"

  minmax_sheets = [
    {
      name: "Aldric Ironwall",
      character_class: "Fighter",
      race: "Human",
      subclass: "Two-Handed Fighter",
      level: 5,
      strength: 20,
      dexterity: 12,
      constitution: 16,
      intelligence: 8,
      wisdom: 10,
      charisma: 7,
      currency: { "gold" => 150, "silver" => 0, "copper" => 0, "platinum" => 0 }
    },
    {
      name: "Vex Nightwhisper",
      character_class: "Rogue",
      race: "Elf",
      subclass: "Knife Master",
      level: 5,
      strength: 8,
      dexterity: 20,
      constitution: 12,
      intelligence: 14,
      wisdom: 10,
      charisma: 10,
      currency: { "gold" => 200, "silver" => 50, "copper" => 0, "platinum" => 0 }
    }
  ]

  [[admin, 0], [test_user, 1]].each do |user, sheet_idx|
    unless user.sheets.exists?
      user.sheets.create!(minmax_sheets[sheet_idx])
      puts "Created sheet '#{minmax_sheets[sheet_idx][:name]}' for #{user.email}"
    end
  end
end
