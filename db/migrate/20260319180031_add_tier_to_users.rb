class AddTierToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :tier, :string, default: "free", null: false
  end
end
