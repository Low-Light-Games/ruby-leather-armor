# frozen_string_literal: true

class CreateEncounterAndLocationTables < ActiveRecord::Migration[7.1]
  def change
    create_table :story_locations do |t|
      t.references :story, null: false, foreign_key: true
      t.string  :name,        null: false
      t.text    :description
      t.boolean :starting,    null: false, default: false
      t.timestamps
    end

    add_index :story_locations, [:story_id, :name], unique: true

    create_table :location_connections do |t|
      t.references :from_location, null: false, foreign_key: { to_table: :story_locations }
      t.references :to_location,   null: false, foreign_key: { to_table: :story_locations }
      t.decimal :distance_miles,   null: false, precision: 8, scale: 2
      t.string  :terrain_type,     null: false, default: "road"
      t.text    :description
      t.timestamps
    end

    add_index :location_connections, [:from_location_id, :to_location_id], unique: true,
              name: "idx_location_connections_pair"

    create_table :encounter_tables do |t|
      t.references :story, null: true, foreign_key: true
      t.string  :name,                  null: false
      t.text    :description
      t.integer :check_frequency_hours, null: false, default: 4
      t.integer :encounter_chance,      null: false, default: 15
      t.timestamps
    end

    create_table :encounter_table_entries do |t|
      t.references :encounter_table, null: false, foreign_key: true
      t.string  :title,       null: false
      t.text    :description, null: false
      t.string  :entry_type,  null: false, default: "fixed"
      t.integer :weight,      null: false, default: 1
      t.string  :terrain_types
      t.integer :min_party_level
      t.integer :max_party_level
      t.timestamps
    end

    add_reference :adventures, :current_location, foreign_key: { to_table: :story_locations }, null: true
  end
end
