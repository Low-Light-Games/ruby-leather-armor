class AddInitialContextsToStories < ActiveRecord::Migration[7.1]
  def change
    add_column :stories, :initial_contexts, :jsonb, default: {}, null: false
  end
end
