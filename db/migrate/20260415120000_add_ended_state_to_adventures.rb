# frozen_string_literal: true

class AddEndedStateToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :ended_at, :datetime
    add_column :adventures, :end_reason, :string
    add_index :adventures, :ended_at
  end
end
