class ChangeEncounterTableEntriesDescriptionNullable < ActiveRecord::Migration[7.1]
  def change
    change_column_null :encounter_table_entries, :description, true
  end
end
