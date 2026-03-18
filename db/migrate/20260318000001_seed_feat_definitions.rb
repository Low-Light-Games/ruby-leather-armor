class SeedFeatDefinitions < ActiveRecord::Migration[7.1]
  def up
    load Rails.root.join("db", "seeds", "feats.rb")
  end

  def down
    # Reference data is never auto-deleted on rollback
  end
end
