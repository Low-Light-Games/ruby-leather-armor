# frozen_string_literal: true

namespace :ops do
  desc "Sync production game catalogs (feats, spells, items, class abilities, feature flags)"
  task sync_game_catalogs: :environment do
    unless Rails.env.production?
      abort "[ops:sync_game_catalogs] Refusing to run outside production (RAILS_ENV=#{Rails.env})."
    end

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    puts "[ops:sync_game_catalogs] Starting catalog sync..."

    seed_files = [
      "feats.rb",
      "spells.rb",
      "items.rb",
      "class_abilities.rb",
      "feature_flags.rb"
    ]

    seed_files.each do |seed_file|
      full_path = Rails.root.join("db", "seeds", seed_file)
      puts "[ops:sync_game_catalogs] Loading #{full_path}..."
      load full_path.to_s
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    puts "[ops:sync_game_catalogs] Completed in #{format('%.2f', elapsed)}s."
    puts "[ops:sync_game_catalogs] Counts: "\
         "feats=#{FeatDefinition.count}, "\
         "spells=#{SpellDefinition.count}, "\
         "items=#{ItemDefinition.count}, "\
         "class_abilities=#{ClassAbilityDefinition.count}, "\
         "feature_flags=#{FeatureFlag.count}"
  end
end
