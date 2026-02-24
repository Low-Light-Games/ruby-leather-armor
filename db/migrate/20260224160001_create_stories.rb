class CreateStories < ActiveRecord::Migration[7.1]
  def change
    create_table :stories do |t|
      t.string :title, null: false
      t.text :premise, null: false

      t.timestamps
    end
  end
end
