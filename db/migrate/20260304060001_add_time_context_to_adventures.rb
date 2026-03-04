# frozen_string_literal: true

class AddTimeContextToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :time_context, :jsonb, default: {
      "current_hour" => 8,
      "adventure_day" => 1,
      "light_conditions" => "day",
      "hours_since_last_rest" => 0,
      "hours_since_last_encounter_check" => 0
    }, null: false
  end
end
