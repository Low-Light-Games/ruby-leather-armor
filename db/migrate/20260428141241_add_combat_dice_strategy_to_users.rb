class AddCombatDiceStrategyToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :combat_dice_strategy, :string, null: false, default: "client"
  end
end
