# frozen_string_literal: true

class MigrateAdventureSnapshots < ActiveRecord::Migration[7.1]
  def up
    # Migrate each existing adventure's character_snapshot JSON into a real Sheet copy
    execute <<~SQL
      INSERT INTO sheets (
        user_id, name, description, strength, intelligence, dexterity,
        constitution, wisdom, charisma, race, racial_bonus_attribute,
        character_class, details, level, snapshot, created_at, updated_at
      )
      SELECT
        a.user_id,
        COALESCE(a.character_snapshot->>'name', 'Unknown'),
        a.character_snapshot->>'description',
        COALESCE((a.character_snapshot->>'strength')::int, 10),
        COALESCE((a.character_snapshot->>'intelligence')::int, 10),
        COALESCE((a.character_snapshot->>'dexterity')::int, 10),
        COALESCE((a.character_snapshot->>'constitution')::int, 10),
        COALESCE((a.character_snapshot->>'wisdom')::int, 10),
        COALESCE((a.character_snapshot->>'charisma')::int, 10),
        a.character_snapshot->>'race',
        a.character_snapshot->>'racial_bonus_attribute',
        a.character_snapshot->>'character_class',
        json_build_object(
          'feats',  COALESCE(a.character_snapshot->'feats', '[]'::json),
          'spells', COALESCE(a.character_snapshot->'spells', '[]'::json)
        ),
        1,
        true,
        NOW(),
        NOW()
      FROM adventures a
      WHERE a.character_snapshot IS NOT NULL
        AND a.character_snapshot::text != '{}'
    SQL

    # Create snapshot pivot entries: link each adventure to the newly created snapshot sheet.
    # We match by user_id + name + snapshot=true + created time (just created above).
    # A safer approach: use a subquery matching the adventure's data.
    execute <<~SQL
      INSERT INTO adventure_sheets (adventure_id, sheet_id, role, created_at, updated_at)
      SELECT DISTINCT ON (a.id)
        a.id,
        s.id,
        'snapshot',
        NOW(),
        NOW()
      FROM adventures a
      JOIN sheets s ON
        s.user_id = a.user_id
        AND s.snapshot = true
        AND s.name = COALESCE(a.character_snapshot->>'name', 'Unknown')
        AND s.created_at >= (NOW() - INTERVAL '5 minutes')
      WHERE a.character_snapshot IS NOT NULL
        AND a.character_snapshot::text != '{}'
      ORDER BY a.id, s.id DESC
    SQL

    # Create original pivot entries: link each adventure to its original sheet
    execute <<~SQL
      INSERT INTO adventure_sheets (adventure_id, sheet_id, role, created_at, updated_at)
      SELECT
        a.id,
        a.sheet_id,
        'original',
        NOW(),
        NOW()
      FROM adventures a
      WHERE a.sheet_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM sheets WHERE id = a.sheet_id)
        AND NOT EXISTS (
          SELECT 1 FROM adventure_sheets
          WHERE adventure_id = a.id AND role = 'original'
        )
    SQL

    # Remove old columns
    remove_column :adventures, :character_snapshot
    remove_foreign_key :adventures, :sheets
    remove_column :adventures, :sheet_id
  end

  def down
    add_column :adventures, :character_snapshot, :json, default: {}, null: false
    add_reference :adventures, :sheet, foreign_key: true

    # Restore data from pivot
    Adventure.find_each do |adventure|
      snapshot_link = AdventureSheet.find_by(adventure_id: adventure.id, role: 'snapshot')
      original_link = AdventureSheet.find_by(adventure_id: adventure.id, role: 'original')

      if snapshot_link
        sheet = Sheet.find(snapshot_link.sheet_id)
        adventure.update_columns(
          character_snapshot: {
            name: sheet.name,
            description: sheet.description,
            strength: sheet.strength,
            intelligence: sheet.intelligence,
            dexterity: sheet.dexterity,
            constitution: sheet.constitution,
            wisdom: sheet.wisdom,
            charisma: sheet.charisma,
            race: sheet.race,
            racial_bonus_attribute: sheet.racial_bonus_attribute,
            character_class: sheet.character_class,
            feats: sheet.details&.dig('feats') || [],
            spells: sheet.details&.dig('spells') || []
          }
        )
      end

      if original_link
        adventure.update_columns(sheet_id: original_link.sheet_id)
      end
    end
  end
end
