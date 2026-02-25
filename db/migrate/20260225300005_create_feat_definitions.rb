# frozen_string_literal: true

class CreateFeatDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :feat_definitions, id: false do |t|
      t.string :id, primary_key: true, null: false # e.g. "power_attack"
      t.string :name, null: false
      t.string :category, null: false # combat, general, metamagic, item_creation
      t.text   :summary
      t.boolean :repeatable, default: false, null: false
      t.string  :choice_type # weapon, skill, school — NULL for non-parameterised
      t.jsonb  :prerequisites, default: [], null: false
      t.jsonb  :effects, default: [], null: false
      t.timestamps
    end

    add_index :feat_definitions, :category
    add_index :feat_definitions, :name
  end
end
