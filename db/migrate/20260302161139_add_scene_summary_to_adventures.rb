class AddSceneSummaryToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :scene_summary, :text
  end
end
