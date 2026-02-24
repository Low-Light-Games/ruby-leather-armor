class CreateStoryStates < ActiveRecord::Migration[7.1]
  def change
    create_table :story_states do |t|
      t.references :story, null: false, foreign_key: true

      t.timestamps
    end
  end
end
