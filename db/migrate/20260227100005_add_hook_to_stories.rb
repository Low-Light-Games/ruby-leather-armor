class AddHookToStories < ActiveRecord::Migration[7.1]
  def change
    add_column :stories, :hook, :text
  end
end
