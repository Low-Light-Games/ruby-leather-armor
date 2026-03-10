class CreateItemDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :item_definitions, id: :string do |t|
      t.string  :name,                null: false
      t.string  :item_type,           null: false
      t.string  :category
      t.integer :cost,                null: false, default: 0
      t.decimal :weight,              null: false, default: 0
      t.integer :ac_bonus,            default: 0
      t.integer :max_dex_bonus
      t.integer :armor_check_penalty, default: 0
      t.integer :speed_30
      t.integer :speed_20

      t.timestamps
    end

    add_index :item_definitions, :name
    add_index :item_definitions, :item_type
    add_index :item_definitions, :category
  end
end
