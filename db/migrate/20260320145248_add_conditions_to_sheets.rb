class AddConditionsToSheets < ActiveRecord::Migration[7.1]
  def change
    add_column :adventure_sheets, :conditions, :jsonb, default: [], null: false
    add_column :creature_sheets, :conditions, :jsonb, default: [], null: false
  end
end
