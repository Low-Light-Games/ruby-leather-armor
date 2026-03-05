class AddSceneHistoryToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :scene_history, :jsonb, default: [], null: false
  end
end
