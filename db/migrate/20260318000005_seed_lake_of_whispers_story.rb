class SeedLakeOfWhispersStory < ActiveRecord::Migration[7.1]
  def up
    # Data seeding moved to db/seeds.rb — run bin/rails db:seed to populate.
  end

  def down
    # Story content is never auto-deleted on rollback
  end
end
