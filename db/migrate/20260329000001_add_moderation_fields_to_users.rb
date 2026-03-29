# frozen_string_literal: true

class AddModerationFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :moderation_strikes, :integer, null: false, default: 0
    add_column :users, :banned,             :boolean, null: false, default: false
    add_column :users, :banned_at,          :datetime
    add_column :users, :trusted,            :boolean, null: false, default: false
  end
end
