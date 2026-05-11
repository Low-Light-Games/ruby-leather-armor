# frozen_string_literal: true

class AddStoryIdAndDefaultForTypeToBestiaryEntries < ActiveRecord::Migration[7.1]
  def change
    add_reference :bestiary_entries, :story, foreign_key: true, null: true, index: true

    add_column :bestiary_entries, :default_for_type, :string
    add_index  :bestiary_entries, :default_for_type,
               unique: true,
               where: "default_for_type IS NOT NULL",
               name: "index_bestiary_entries_on_default_for_type_unique"
  end
end
