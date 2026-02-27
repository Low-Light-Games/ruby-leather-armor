# frozen_string_literal: true

class AddCurrentCategoryToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :current_category, :string
  end
end
