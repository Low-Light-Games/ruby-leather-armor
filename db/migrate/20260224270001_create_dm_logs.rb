class CreateDmLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :dm_logs do |t|
      t.references :adventure, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false

      t.timestamps
    end

    add_index :dm_logs, :created_at
  end
end
