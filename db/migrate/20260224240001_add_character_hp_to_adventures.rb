class AddCharacterHpToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :character_hp, :integer, null: false, default: 0
    add_column :adventures, :character_max_hp, :integer, null: false, default: 0
  end
end
