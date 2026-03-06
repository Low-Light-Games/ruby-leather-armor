class AddOriginToCreatureSheets < ActiveRecord::Migration[7.1]
  def change
    add_column :creature_sheets, :origin, :string, default: "unknown"
  end
end
