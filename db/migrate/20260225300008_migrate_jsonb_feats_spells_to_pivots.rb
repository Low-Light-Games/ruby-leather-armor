# frozen_string_literal: true

# Data migration: move feat/spell selections from the JSONB `details` column
# into the new pivot tables (sheet_feats, sheet_spells,
# adventure_sheet_feats, adventure_sheet_spells).
#
# After migration, the `feats`, `knownSpells`, `spellbook`, and `spells` keys
# are removed from `details`.

class MigrateJsonbFeatsSpellsToPivots < ActiveRecord::Migration[7.1]
  def up
    # ── Sheets ──────────────────────────────────────────────
    Sheet.find_each do |sheet|
      details = sheet.details || {}

      # Feats — stored as array of strings (may include compound "feat_id::choice")
      (details["feats"] || []).each do |entry|
        parts = entry.split("::", 2)
        feat_id = parts[0]
        choice  = parts[1] # nil if no separator

        next unless FeatDefinition.exists?(feat_id)

        SheetFeat.find_or_create_by!(
          sheet: sheet,
          feat_id: feat_id,
          choice: choice,
        )
      end

      # Spells — known (spontaneous casters)
      (details["knownSpells"] || details["known_spells"] || []).each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)

        SheetSpell.find_or_create_by!(
          sheet: sheet,
          spell_id: spell_id,
          storage_type: "known",
        )
      end

      # Spells — spellbook (wizard)
      (details["spellbook"] || []).each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)

        SheetSpell.find_or_create_by!(
          sheet: sheet,
          spell_id: spell_id,
          storage_type: "spellbook",
        )
      end

      # Legacy `spells` key (treat as "known")
      (details["spells"] || []).each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)

        SheetSpell.find_or_create_by!(
          sheet: sheet,
          spell_id: spell_id,
          storage_type: "known",
        )
      end

      # Clean up JSONB
      %w[feats knownSpells known_spells spellbook spells].each { |k| details.delete(k) }
      sheet.update_column(:details, details)
    end

    # ── Adventure Sheets ────────────────────────────────────
    AdventureSheet.find_each do |as|
      details = as.details || {}

      (details["feats"] || []).each do |entry|
        parts = entry.split("::", 2)
        feat_id = parts[0]
        choice  = parts[1]

        next unless FeatDefinition.exists?(feat_id)

        AdventureSheetFeat.find_or_create_by!(
          adventure_sheet: as,
          feat_id: feat_id,
          choice: choice,
        )
      end

      (details["knownSpells"] || details["known_spells"] || []).each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)

        AdventureSheetSpell.find_or_create_by!(
          adventure_sheet: as,
          spell_id: spell_id,
          storage_type: "known",
        )
      end

      (details["spellbook"] || []).each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)

        AdventureSheetSpell.find_or_create_by!(
          adventure_sheet: as,
          spell_id: spell_id,
          storage_type: "spellbook",
        )
      end

      (details["spells"] || []).each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)

        AdventureSheetSpell.find_or_create_by!(
          adventure_sheet: as,
          spell_id: spell_id,
          storage_type: "known",
        )
      end

      %w[feats knownSpells known_spells spellbook spells].each { |k| details.delete(k) }
      as.update_column(:details, details)
    end
  end

  def down
    # Reverse: read pivot tables back into JSONB
    Sheet.find_each do |sheet|
      details = sheet.details || {}
      details["feats"] = sheet.sheet_feats.map { |sf|
        sf.choice ? "#{sf.feat_id}::#{sf.choice}" : sf.feat_id
      }
      details["knownSpells"] = sheet.sheet_spells.where(storage_type: "known").pluck(:spell_id)
      details["spellbook"] = sheet.sheet_spells.where(storage_type: "spellbook").pluck(:spell_id)
      sheet.update_column(:details, details)
    end

    AdventureSheet.find_each do |as|
      details = as.details || {}
      details["feats"] = as.adventure_sheet_feats.map { |sf|
        sf.choice ? "#{sf.feat_id}::#{sf.choice}" : sf.feat_id
      }
      details["knownSpells"] = as.adventure_sheet_spells.where(storage_type: "known").pluck(:spell_id)
      details["spellbook"] = as.adventure_sheet_spells.where(storage_type: "spellbook").pluck(:spell_id)
      as.update_column(:details, details)
    end
  end
end
