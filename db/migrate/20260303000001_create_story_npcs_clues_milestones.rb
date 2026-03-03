# frozen_string_literal: true

class CreateStoryNpcsCluesMilestones < ActiveRecord::Migration[7.1]
  def change
    create_table :story_npcs do |t|
      t.references :story, null: false, foreign_key: true
      t.references :adventure, null: true, foreign_key: true
      t.string  :source,      null: false, default: "manual"
      t.string  :name,        null: false
      t.string  :role,        null: false, default: "bystander"
      t.references :location, null: true, foreign_key: { to_table: :story_locations }
      t.text    :description
      t.text    :knowledge
      t.string  :attitude,    null: false, default: "indifferent"
      t.boolean :secret,      null: false, default: false
      t.timestamps
    end

    create_table :story_clues do |t|
      t.references :story, null: false, foreign_key: true
      t.references :adventure, null: true, foreign_key: true
      t.string  :source,           null: false, default: "manual"
      t.string  :title,            null: false
      t.text    :description,      null: false
      t.string  :discovery_method, null: false, default: "exploration"
      t.references :location, null: true, foreign_key: { to_table: :story_locations }
      t.references :npc, null: true, foreign_key: { to_table: :story_npcs }
      t.integer :prerequisite_clue_ids, array: true, default: []
      t.text    :reveals_secret
      t.string  :difficulty,       null: false, default: "moderate"
      t.timestamps
    end

    create_table :story_milestones do |t|
      t.references :story, null: false, foreign_key: true
      t.string  :source,      null: false, default: "manual"
      t.string  :title,       null: false
      t.text    :description,  null: false
      t.integer :trigger_clue_ids, array: true, default: []
      t.text    :consequence
      t.timestamps
    end
  end
end
