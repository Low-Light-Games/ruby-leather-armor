# frozen_string_literal: true

class RetireStoryStates < ActiveRecord::Migration[7.1]
  def up
    add_reference :adventures, :story, foreign_key: true

    execute <<-SQL
      UPDATE adventures
      SET story_id = story_states.story_id
      FROM story_states
      WHERE adventures.story_state_id = story_states.id
    SQL

    change_column_null :adventures, :story_id, false

    remove_foreign_key :adventures, :story_states
    remove_column :adventures, :story_state_id

    drop_table :story_states
  end

  def down
    create_table :story_states do |t|
      t.references :story, null: false, foreign_key: true
      t.text :description, default: "", null: false
      t.integer :position, default: 0, null: false
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :story_states, :discarded_at

    add_reference :adventures, :story_state, foreign_key: true

    remove_foreign_key :adventures, :stories
    remove_reference :adventures, :story
  end
end
