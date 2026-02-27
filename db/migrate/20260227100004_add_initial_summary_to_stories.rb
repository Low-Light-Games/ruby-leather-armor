class AddInitialSummaryToStories < ActiveRecord::Migration[7.1]
  def change
    add_column :stories, :initial_summary, :text
  end
end
