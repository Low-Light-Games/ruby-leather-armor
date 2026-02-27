# frozen_string_literal: true

class CreateLocationEdges < ActiveRecord::Migration[7.1]
  def change
    create_table :location_edges do |t|
      t.references :from_location, null: false, foreign_key: { to_table: :locations }
      t.references :to_location, null: false, foreign_key: { to_table: :locations }
      t.decimal :distance_miles, precision: 8, scale: 2, null: false
      t.string :terrain_type, default: "road"
      t.text :description

      t.timestamps
    end

    add_index :location_edges, [:from_location_id, :to_location_id], unique: true
  end
end
