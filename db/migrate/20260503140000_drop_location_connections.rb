# frozen_string_literal: true

# Drops the location_connections table now that journey-time math reads
# (x, y) coordinates from `adventure_locations` and a single global
# `Story.world_terrain`. All consumers are repointed in the same commit.
class DropLocationConnections < ActiveRecord::Migration[7.1]
  def up
    drop_table :location_connections
  end

  def down
    create_table :location_connections do |t|
      t.bigint  :from_location_id, null: false
      t.bigint  :to_location_id,   null: false
      t.decimal :distance_miles, precision: 8, scale: 2, null: false
      t.string  :terrain_type, default: "road", null: false
      t.text    :description
      t.timestamps
    end
    add_index :location_connections, [:from_location_id, :to_location_id],
              unique: true, name: "idx_location_connections_pair"
    add_index :location_connections, :from_location_id
    add_index :location_connections, :to_location_id
  end
end
