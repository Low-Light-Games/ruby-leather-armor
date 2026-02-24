class CreateAdventures < ActiveRecord::Migration[7.1]
  def change
    create_table :adventures do |t|
      t.references :sheet, null: false, foreign_key: true
      t.references :story_state, null: false, foreign_key: true
      t.text :character_effects
      t.integer :character_gold, default: 0, null: false
      t.text :character_items

      t.timestamps
    end
  end
end
