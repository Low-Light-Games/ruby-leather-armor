class AddSourceKindAndStarterKeyToSheets < ActiveRecord::Migration[7.1]
  def change
    add_column :sheets, :source_kind, :string, null: false, default: "custom"
    add_column :sheets, :starter_key, :string

    add_index :sheets, :source_kind
    add_index :sheets, [:user_id, :starter_key], unique: true, where: "starter_key IS NOT NULL"
  end
end
