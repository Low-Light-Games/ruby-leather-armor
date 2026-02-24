class AddPreviewToStories < ActiveRecord::Migration[7.1]
  def change
    add_column :stories, :preview, :text, null: false, default: ''
  end
end
