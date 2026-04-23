class RemoveTierFromUsers < ActiveRecord::Migration[7.1]
  def change
    remove_column :users, :tier, :string
  end
end
