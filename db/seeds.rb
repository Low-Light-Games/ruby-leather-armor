# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Reference / catalog data — needed in all environments
load Rails.root.join("db", "seeds", "feats.rb")
load Rails.root.join("db", "seeds", "spells.rb")
load Rails.root.join("db", "seeds", "items.rb")
load Rails.root.join("db", "seeds", "bestiary.rb")

# Story content — must run before encounter_tables, which depends on stories existing
load Rails.root.join("db", "seeds", "lake_of_whispers_story.rb")
load Rails.root.join("db", "seeds", "encounter_tables.rb")

# Only bootstrap local development — production admin accounts should be
# created through a secure out-of-band process.
if Rails.env.development? || Rails.env.staging?
  admin = User.find_or_initialize_by(email: 'admin@example.com')
  admin.admin = true
  admin.password = 'admin123'
  admin.save!

  test_user = User.find_or_initialize_by(email: 'test@example.com')
  test_user.admin = false
  test_user.password = 'test123'
  test_user.save!

  puts "Created/updated admin user: #{admin.email} (password: admin123)"
  puts "Created/updated test user: #{test_user.email} (password: test123)"

  [admin, test_user].each do |u|
    unless u.sheets.exists?
      u.sheets.create!(
        name: "Aldric Stonebrow",
        character_class: "Fighter",
        strength: 15,
        dexterity: 13,
        constitution: 14,
        intelligence: 10,
        wisdom: 12,
        charisma: 8
      )
      puts "Created sheet for #{u.email}"
    end
  end
end
