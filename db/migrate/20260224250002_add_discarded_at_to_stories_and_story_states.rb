class AddDiscardedAtToStoriesAndStoryStates < ActiveRecord::Migration[7.1]
  def change
    add_column :stories, :discarded_at, :datetime, null: true
    add_column :story_states, :discarded_at, :datetime, null: true

    add_index :stories, :discarded_at
    add_index :story_states, :discarded_at
  end
end
