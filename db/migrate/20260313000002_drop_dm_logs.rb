class DropDmLogs < ActiveRecord::Migration[7.1]
  def up
    drop_table :dm_logs
  end

  def down
    create_table :dm_logs do |t|
      t.bigint :adventure_id
      t.bigint :user_id, null: false
      t.text :content, null: false
      t.timestamps
    end
    add_index :dm_logs, :adventure_id
    add_index :dm_logs, :user_id
    add_foreign_key :dm_logs, :adventures, on_delete: :nullify
    add_foreign_key :dm_logs, :users
  end
end
