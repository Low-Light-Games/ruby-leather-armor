# frozen_string_literal: true

class CreateModerationEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :moderation_events do |t|
      t.references :user,              null: false, foreign_key: true
      t.text       :input_excerpt
      t.jsonb      :flagged_categories, null: false, default: {}
      t.integer    :strike_number,      null: false
      t.boolean    :auto_banned,        null: false, default: false
      t.boolean    :auto_untrusted,     null: false, default: false

      t.timestamps
    end

    add_index :moderation_events, :created_at
  end
end
