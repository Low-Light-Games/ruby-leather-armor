# frozen_string_literal: true

class AddDiscardedAtToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :discarded_at, :datetime
    add_index  :adventures, :discarded_at
  end
end
