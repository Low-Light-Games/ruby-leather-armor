# frozen_string_literal: true

class CreateClassAbilityDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :class_ability_definitions, id: :string, force: :cascade do |t|
      t.string :name,       null: false
      t.string :pf1e_class, null: false
      t.text   :summary

      t.timestamps
    end

    add_index :class_ability_definitions, :name
    add_index :class_ability_definitions, :pf1e_class
  end
end
