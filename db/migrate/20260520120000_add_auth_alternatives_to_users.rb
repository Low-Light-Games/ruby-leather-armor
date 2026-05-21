# frozen_string_literal: true

class AddAuthAlternativesToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :handle, :string
    add_column :users, :guest_ip_hash, :string
    add_column :users, :guest_created_at, :datetime
    add_column :users, :password_reset_token, :string
    add_column :users, :password_reset_sent_at, :datetime
    add_column :users, :email_verified_at, :datetime

    add_index :users, "LOWER(handle)", unique: true, where: "handle IS NOT NULL", name: "index_users_on_lower_handle"
    add_index :users, :guest_ip_hash, unique: true, where: "guest_ip_hash IS NOT NULL"
    add_index :users, :password_reset_token, unique: true, where: "password_reset_token IS NOT NULL"
  end
end
