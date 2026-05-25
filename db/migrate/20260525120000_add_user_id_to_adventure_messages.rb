# frozen_string_literal: true

class AddUserIdToAdventureMessages < ActiveRecord::Migration[7.1]
  def change
    add_reference :adventure_messages, :user, null: true, foreign_key: true, index: false
    add_index :adventure_messages, [:user_id, :created_at]
  end
end
