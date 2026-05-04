# frozen_string_literal: true

class RepointCurrentLocationToAdventureLocations < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :adventures, column: :current_location_id

    Adventure.reset_column_information
    Adventure.where.not(current_location_id: nil).find_each do |adventure|
      mapped = AdventureLocation.where(adventure_id: adventure.id,
                                       story_location_id: adventure.current_location_id).first
      adventure.update_columns(current_location_id: mapped&.id)
    end

    add_foreign_key :adventures, :adventure_locations, column: :current_location_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :adventures, column: :current_location_id

    Adventure.reset_column_information
    Adventure.where.not(current_location_id: nil).find_each do |adventure|
      adv_loc = AdventureLocation.find_by(id: adventure.current_location_id)
      adventure.update_columns(current_location_id: adv_loc&.story_location_id)
    end

    add_foreign_key :adventures, :story_locations, column: :current_location_id
  end
end
