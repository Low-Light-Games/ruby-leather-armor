# frozen_string_literal: true

class RenameCreatureSheetToAdventureActorSheet < ActiveRecord::Migration[7.1]
  def change
    rename_table :creature_sheets,        :adventure_actor_sheets
    rename_table :creature_sheet_feats,   :adventure_actor_sheet_feats
    rename_table :creature_sheet_items,   :adventure_actor_sheet_items
    rename_table :creature_sheet_spells,  :adventure_actor_sheet_spells

    rename_column :adventure_actor_sheet_feats,  :creature_sheet_id, :actor_sheet_id
    rename_column :adventure_actor_sheet_items,  :creature_sheet_id, :actor_sheet_id
    rename_column :adventure_actor_sheet_spells, :creature_sheet_id, :actor_sheet_id
    rename_column :adventure_npcs,               :creature_sheet_id, :actor_sheet_id

    rename_index :adventure_actor_sheet_feats,
                 "idx_creature_sheet_feats_unique",
                 "idx_adventure_actor_sheet_feats_unique"
    rename_index :adventure_actor_sheet_spells,
                 "idx_creature_sheet_spells_unique",
                 "idx_adventure_actor_sheet_spells_unique"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE adventures
          SET combat_context = jsonb_set(
            combat_context,
            '{participants}',
            (
              SELECT jsonb_agg(
                p - 'creature_sheet_id'
                  || jsonb_build_object('actor_sheet_id', p->'creature_sheet_id')
              )
              FROM jsonb_array_elements(combat_context->'participants') p
            )
          )
          WHERE combat_context ? 'participants'
            AND jsonb_typeof(combat_context->'participants') = 'array'
            AND jsonb_array_length(combat_context->'participants') > 0
            AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(combat_context->'participants') p2
              WHERE p2 ? 'creature_sheet_id'
            )
        SQL

        execute <<~SQL
          UPDATE adventure_loops
          SET data = jsonb_set(
            data,
            '{cast_roster, entries}',
            (
              SELECT jsonb_agg(
                e - 'creature_sheet_id'
                  || jsonb_build_object('actor_sheet_id', e->'creature_sheet_id')
              )
              FROM jsonb_array_elements(data->'cast_roster'->'entries') e
            )
          )
          WHERE data ? 'cast_roster'
            AND data->'cast_roster' ? 'entries'
            AND jsonb_typeof(data->'cast_roster'->'entries') = 'array'
            AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(data->'cast_roster'->'entries') e2
              WHERE e2 ? 'creature_sheet_id'
            )
        SQL
      end

      dir.down do
        execute <<~SQL
          UPDATE adventure_loops
          SET data = jsonb_set(
            data,
            '{cast_roster, entries}',
            (
              SELECT jsonb_agg(
                e - 'actor_sheet_id'
                  || jsonb_build_object('creature_sheet_id', e->'actor_sheet_id')
              )
              FROM jsonb_array_elements(data->'cast_roster'->'entries') e
            )
          )
          WHERE data ? 'cast_roster'
            AND data->'cast_roster' ? 'entries'
            AND jsonb_typeof(data->'cast_roster'->'entries') = 'array'
            AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(data->'cast_roster'->'entries') e2
              WHERE e2 ? 'actor_sheet_id'
            )
        SQL

        execute <<~SQL
          UPDATE adventures
          SET combat_context = jsonb_set(
            combat_context,
            '{participants}',
            (
              SELECT jsonb_agg(
                p - 'actor_sheet_id'
                  || jsonb_build_object('creature_sheet_id', p->'actor_sheet_id')
              )
              FROM jsonb_array_elements(combat_context->'participants') p
            )
          )
          WHERE combat_context ? 'participants'
            AND jsonb_typeof(combat_context->'participants') = 'array'
            AND jsonb_array_length(combat_context->'participants') > 0
            AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(combat_context->'participants') p2
              WHERE p2 ? 'actor_sheet_id'
            )
        SQL
      end
    end
  end
end
