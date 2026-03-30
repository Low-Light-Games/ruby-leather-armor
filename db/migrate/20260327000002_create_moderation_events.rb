class CreateModerationEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :moderation_events do |t|
      t.references :user, null: false, foreign_key: true
      t.text :input_excerpt
      t.jsonb :flagged_categories, default: {}, null: false
      t.integer :strike_number, null: false
      t.boolean :auto_banned, default: false, null: false
      t.boolean :auto_untrusted, default: false, null: false

      t.timestamps
    end

    add_index :moderation_events, :created_at
  end
end
