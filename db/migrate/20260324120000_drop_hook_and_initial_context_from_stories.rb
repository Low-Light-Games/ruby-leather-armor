class DropHookAndInitialContextFromStories < ActiveRecord::Migration[7.1]
  def change
    remove_column :stories, :hook, :text
    remove_column :stories, :initial_context, :text
  end
end
