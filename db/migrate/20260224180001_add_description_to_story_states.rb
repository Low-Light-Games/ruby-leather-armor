class AddDescriptionToStoryStates < ActiveRecord::Migration[7.1]
  def change
    add_column :story_states, :description, :text, null: false, default: ''
  end
end
