# frozen_string_literal: true

class AddGoldToSheets < ActiveRecord::Migration[7.1]
  def change
    add_column :sheets, :gold, :integer, null: false, default: 0
  end
end
