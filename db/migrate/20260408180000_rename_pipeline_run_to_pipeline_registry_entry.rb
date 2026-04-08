# frozen_string_literal: true

class RenamePipelineRunToPipelineRegistryEntry < ActiveRecord::Migration[7.1]
  def up
    rename_table :pipeline_runs, :pipeline_registry_entries
    rename_column :pipeline_registry_entries, :pipeline_run_id, :registry_entry_uuid

    rename_column :adventure_loops, :pipeline_run_id, :registry_entry_uuid
    rename_column :ai_usage_records, :pipeline_run_id, :registry_entry_uuid
    rename_column :experience_suggestions, :pipeline_run_id, :registry_entry_uuid
    rename_column :play_logs, :pipeline_run_id, :registry_entry_uuid

    say_with_time "Rewriting adventure_messages.metadata pipeline_run_id -> registry_entry_uuid" do
      execute <<-SQL.squish
        UPDATE adventure_messages
        SET metadata = (metadata::jsonb - 'pipeline_run_id') ||
          jsonb_build_object('registry_entry_uuid', metadata::jsonb->'pipeline_run_id')
        WHERE metadata::jsonb ? 'pipeline_run_id'
      SQL
    end
  end

  def down
    say_with_time "Reverting adventure_messages.metadata" do
      execute <<-SQL.squish
        UPDATE adventure_messages
        SET metadata = (metadata::jsonb - 'registry_entry_uuid') ||
          jsonb_build_object('pipeline_run_id', metadata::jsonb->'registry_entry_uuid')
        WHERE metadata::jsonb ? 'registry_entry_uuid'
      SQL
    end

    rename_column :play_logs, :registry_entry_uuid, :pipeline_run_id
    rename_column :experience_suggestions, :registry_entry_uuid, :pipeline_run_id
    rename_column :ai_usage_records, :registry_entry_uuid, :pipeline_run_id
    rename_column :adventure_loops, :registry_entry_uuid, :pipeline_run_id
    rename_column :pipeline_registry_entries, :registry_entry_uuid, :pipeline_run_id
    rename_table :pipeline_registry_entries, :pipeline_runs
  end
end
