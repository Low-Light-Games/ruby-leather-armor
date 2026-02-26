class CreateItemDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :item_definitions do |t|

      t.timestamps
    end
  end
end
