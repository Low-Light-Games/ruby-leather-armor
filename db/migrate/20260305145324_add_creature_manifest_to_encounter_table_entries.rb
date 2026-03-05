class AddCreatureManifestToEncounterTableEntries < ActiveRecord::Migration[7.1]
  def change
    add_column :encounter_table_entries, :creature_manifest, :jsonb, default: [], null: false
  end
end
