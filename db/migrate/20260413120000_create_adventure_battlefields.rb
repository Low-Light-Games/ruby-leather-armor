# frozen_string_literal: true

class CreateAdventureBattlefields < ActiveRecord::Migration[7.1]
  def change
    create_table :adventure_battlefields do |t|
      t.references :adventure, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.string :topology, null: false, default: "square"
      t.jsonb :world, null: false, default: {}
      t.jsonb :tokens, null: false, default: {}
      t.jsonb :viewport, null: false, default: {}
      t.integer :version, null: false, default: 1
      t.datetime :archived_at

      t.timestamps
    end

    add_index :adventure_battlefields, [:adventure_id, :status]
  end
end
