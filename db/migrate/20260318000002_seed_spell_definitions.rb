class SeedSpellDefinitions < ActiveRecord::Migration[7.1]
  def up
    # Data seeding moved to db/seeds.rb — run bin/rails db:seed to populate.
  end

  def down
    # Reference data is never auto-deleted on rollback
  end
end
