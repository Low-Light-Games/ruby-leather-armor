# frozen_string_literal: true

class AddPayingUsersAllowedFeatureFlag < ActiveRecord::Migration[7.1]
  def up
    execute <<-SQL.squish
      INSERT INTO feature_flags (key, enabled, description, created_at, updated_at)
      VALUES (
        'paying_users_allowed',
        false,
        'When enabled, users can open plans, checkout, billing portal, and subscription success flows.',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM feature_flags WHERE key = 'paying_users_allowed'"
  end
end
