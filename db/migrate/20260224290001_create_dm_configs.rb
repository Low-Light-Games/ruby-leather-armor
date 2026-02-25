class CreateDmConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :dm_configs do |t|
      t.json :settings, null: false, default: {}
      t.timestamps
    end
  end
end
