# frozen_string_literal: true

class AddBucketingToFeatureFlags < ActiveRecord::Migration[7.1]
  def change
    change_table :feature_flags, bulk: true do |t|
      t.string  :mode, null: false, default: "off"
      t.string  :bucketing_strategy
      t.integer :granular_user_ids, array: true, null: false, default: []
      t.integer :modulo_divisor
      t.integer :modulo_on_remainders, array: true, null: false, default: []
      t.remove  :enabled, type: :boolean, null: false, default: false
    end
  end
end
