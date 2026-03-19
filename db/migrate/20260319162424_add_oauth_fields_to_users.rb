class AddOauthFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    change_column_null :users, :password_digest, true
    add_index :users, [:provider, :uid], unique: true, where: "provider IS NOT NULL"
  end
end
