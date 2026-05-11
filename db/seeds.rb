# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Reference / catalog data — needed in all environments
load Rails.root.join('db', 'seeds', 'feats.rb')
load Rails.root.join('db', 'seeds', 'spells.rb')
load Rails.root.join('db', 'seeds', 'items.rb')
load Rails.root.join('db', 'seeds', 'class_abilities.rb')
load Rails.root.join('db', 'seeds', 'bestiary.rb')
load Rails.root.join('db', 'seeds', 'feature_flags.rb')

# Story content — must run before encounter_tables, which depends on stories existing
load Rails.root.join('db', 'seeds', 'combat_story.rb')
load Rails.root.join('db', 'seeds', 'long_road_story.rb')
load Rails.root.join('db', 'seeds', 'envoys_gambit_story.rb')
load Rails.root.join('db', 'seeds', 'encounter_tables.rb')

def seed_playwright_sidebar_fixture!
  fixture_user = User.find_or_initialize_by(email: 'sidebar-fixture@example.com')
  fixture_user.admin = false
  fixture_user.password = 'sidebar123'
  fixture_user.onboarding_state = 'in_progress'
  fixture_user.save!

  fixture_sheet = Sheets::StarterProvisioner.ensure_for(user: fixture_user, starter_key: 'fighter')
  fixture_sheet.update!(name: 'Aldric Buff Fixture')
  fixture_sheet.recompute_derived_stats!

  story = Story.find_by!(title: 'The Bloodfield March')
  adventure = fixture_user.adventures.kept.find_by(story: story)
  adventure ||= Adventures::Bootstrap.new(story: story, sheet: fixture_sheet, user: fixture_user).call

  adventure_sheet = adventure.adventure_sheets.first!
  adventure_sheet.update!(
    active_buffs: [
      {
        'source' => 'rage',
        'source_type' => 'class_ability',
        'bonus_type' => 'morale',
        'target' => 'strength',
        'value' => 2,
        'expires_at_game_hours' => nil
      },
      {
        'source' => 'mage_armor',
        'source_type' => 'spell',
        'bonus_type' => 'armor',
        'target' => 'ac',
        'value' => 4,
        'expires_at_game_hours' => nil
      },
      {
        'source' => 'fighting_defensively',
        'source_type' => 'class_ability',
        'bonus_type' => 'dodge',
        'target' => 'ac',
        'value' => 2,
        'expires_at_game_hours' => nil
      }
    ],
    conditions: ['shaken']
  )
  adventure_sheet.recompute_derived_stats!

  puts "Created/updated Playwright sidebar fixture: #{fixture_user.email} -> adventure ##{adventure.id}"
end

def seed_playwright_combat_fixture!
  fixture_user = User.find_or_initialize_by(email: 'combat-fixture@example.com')
  fixture_user.admin = false
  fixture_user.password = 'combat123'
  fixture_user.onboarding_state = 'in_progress'
  fixture_user.combat_dice_strategy = 'server'
  fixture_user.save!

  fixture_sheet = Sheets::StarterProvisioner.ensure_for(user: fixture_user, starter_key: 'fighter')
  fixture_sheet.update!(name: 'Combat Aldric')
  fixture_sheet.recompute_derived_stats!

  story = Story.find_by!(title: 'The Bloodfield March')
  fixture_user.adventures.kept.where(story: story).find_each(&:discard!)
  adventure = Adventures::Bootstrap.new(story: story, sheet: fixture_sheet, user: fixture_user).call
  adventure_sheet = adventure.adventure_sheets.first!

  %w[mage_armor cure_light_wounds].each do |spell_id|
    spell = SpellDefinition.find_by(id: spell_id)
    next unless spell

    adventure_sheet.adventure_sheet_spells.find_or_create_by!(spell_id: spell.id, storage_type: 'spellbook')
    fixture_sheet.sheet_spells.find_or_create_by!(spell_id: spell.id, storage_type: 'spellbook')
  end

  adventure.creature_sheets.where(name: ['Goblin Scout', 'Goblin Soldier']).destroy_all
  goblin_attrs = {
    creature_type: 'npc',
    origin: 'template',
    strength: 11, dexterity: 15, constitution: 12, intelligence: 10, wisdom: 9, charisma: 6,
    level: 1, hp: 1, max_hp: 1,
    derived_stats: { 'ac' => 5, 'flat_footed_ac' => 5, 'touch_ac' => 5, 'bab' => 1, 'speed' => 30 },
    equipped_weapons: [{ 'name' => 'short sword', 'weapon_type' => 'melee',
                         'damage' => '1d4', 'damage_type' => 'slashing',
                         'crit_range' => 19, 'crit_multiplier' => 2 }]
  }
  goblins = ['Goblin Scout', 'Goblin Soldier'].map do |name|
    sheet = adventure.creature_sheets.create!(goblin_attrs.merge(name: name))
    sheet.recompute_derived_stats!
    sheet
  end

  creature_data = goblins.map { |g| { creature_sheet_id: g.id, name: g.name, initiative: 1 } }

  combat_data = Encounters::Warmaster.compute_combat_initialization(
    adventure: adventure,
    player_sheet: adventure_sheet,
    creature_data: creature_data,
    player_initiative: 99
  )

  Battlefield::PersistCombatStart.call(
    adventure: adventure, combat_data: combat_data, sheet: adventure_sheet
  )

  puts "Created/updated Playwright combat fixture: #{fixture_user.email} -> adventure ##{adventure.id}"
end

# Only bootstrap local development — production admin accounts should be
# created through a secure out-of-band process.
if Rails.env.development? || Rails.env.staging? || Rails.env.playwright?
  # Skip the character-onboarding wizard for seeded accounts so Playwright (and
  # local smoke tests) land on /adventures/new with story/sheet picks. New users
  # still get onboarding_state "new" from the schema default.
  admin = User.find_or_initialize_by(email: 'admin@example.com')
  admin.admin = true
  admin.password = 'admin123'
  admin.onboarding_state = 'in_progress'
  admin.save!

  test_user = User.find_or_initialize_by(email: 'test@example.com')
  test_user.admin = false
  test_user.password = 'test123'
  test_user.onboarding_state = 'in_progress'
  test_user.save!

  lead_user = User.find_or_initialize_by(email: 'lead@example.com')
  lead_user.admin = false
  lead_user.password = 'lead123'
  lead_user.onboarding_state = 'new'
  lead_user.save!

  # Paid Playwright user — exercises code paths gated on `current_user.paid?`
  # without admin overrides. plan_key 'hero' picks a generous token budget so
  # individual e2e runs are never cut off by the monthly limit.
  paid_user = User.find_or_initialize_by(email: 'paid@example.com')
  paid_user.admin = false
  paid_user.password = 'paid123'
  paid_user.onboarding_state = 'in_progress'
  paid_user.save!

  paid_profile = paid_user.stripe_profile || paid_user.build_stripe_profile
  paid_profile.plan_key = 'hero'
  paid_profile.grace_period_ends_at = nil
  paid_profile.save!

  puts "Created/updated admin user: #{admin.email} (password: admin123)"
  puts "Created/updated test user: #{test_user.email} (password: test123)"
  puts "Created/updated lead user (onboarding new): #{lead_user.email} (password: lead123)"
  puts "Created/updated paid user: #{paid_user.email} (password: paid123, plan: #{paid_profile.plan_key})"

  minmax_sheets = [
    {
      name: 'Aldric Ironwall',
      character_class: 'Fighter',
      race: 'Human',
      subclass: 'Two-Handed Fighter',
      level: 5,
      strength: 20,
      dexterity: 12,
      constitution: 16,
      intelligence: 8,
      wisdom: 10,
      charisma: 7,
      currency: { 'gold' => 150, 'silver' => 0, 'copper' => 0, 'platinum' => 0 }
    },
    {
      name: 'Vex Nightwhisper',
      character_class: 'Rogue',
      race: 'Elf',
      subclass: 'Knife Master',
      level: 5,
      strength: 8,
      dexterity: 20,
      constitution: 12,
      intelligence: 14,
      wisdom: 10,
      charisma: 10,
      currency: { 'gold' => 200, 'silver' => 50, 'copper' => 0, 'platinum' => 0 }
    }
  ]

  [[admin, 0], [test_user, 1], [paid_user, 1]].each do |user, sheet_idx|
    unless user.sheets.exists?
      user.sheets.create!(minmax_sheets[sheet_idx])
      puts "Created sheet '#{minmax_sheets[sheet_idx][:name]}' for #{user.email}"
    end
  end

  if Rails.env.playwright?
    seed_playwright_sidebar_fixture!
    seed_playwright_combat_fixture!
  end
end
