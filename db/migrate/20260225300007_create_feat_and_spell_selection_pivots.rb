# frozen_string_literal: true

class CreateFeatAndSpellSelectionPivots < ActiveRecord::Migration[7.1]
  def change
    # ── Sheet ↔ Feat pivot ──────────────────────────────────
    create_table :sheet_feats do |t|
      t.references :sheet, null: false, foreign_key: true
      t.string     :feat_id, null: false # FK to feat_definitions.id
      t.string     :choice             # e.g. "Perception" for Skill Focus
      t.timestamps
    end

    add_foreign_key :sheet_feats, :feat_definitions, column: :feat_id, primary_key: :id
    add_index :sheet_feats, [:sheet_id, :feat_id, :choice], unique: true, name: "idx_sheet_feats_unique"

    # ── AdventureSheet ↔ Feat pivot ─────────────────────────
    create_table :adventure_sheet_feats do |t|
      t.references :adventure_sheet, null: false, foreign_key: true
      t.string     :feat_id, null: false
      t.string     :choice
      t.timestamps
    end

    add_foreign_key :adventure_sheet_feats, :feat_definitions, column: :feat_id, primary_key: :id
    add_index :adventure_sheet_feats, [:adventure_sheet_id, :feat_id, :choice],
              unique: true, name: "idx_adv_sheet_feats_unique"

    # ── Sheet ↔ Spell pivot ─────────────────────────────────
    create_table :sheet_spells do |t|
      t.references :sheet, null: false, foreign_key: true
      t.string     :spell_id, null: false # FK to spell_definitions.id
      t.string     :storage_type, null: false, default: "known"
      # "known" = spontaneous caster's known spell
      # "spellbook" = wizard's spellbook entry
      t.timestamps
    end

    add_foreign_key :sheet_spells, :spell_definitions, column: :spell_id, primary_key: :id
    add_index :sheet_spells, [:sheet_id, :spell_id, :storage_type],
              unique: true, name: "idx_sheet_spells_unique"

    # ── AdventureSheet ↔ Spell pivot ────────────────────────
    create_table :adventure_sheet_spells do |t|
      t.references :adventure_sheet, null: false, foreign_key: true
      t.string     :spell_id, null: false
      t.string     :storage_type, null: false, default: "known"
      t.timestamps
    end

    add_foreign_key :adventure_sheet_spells, :spell_definitions, column: :spell_id, primary_key: :id
    add_index :adventure_sheet_spells, [:adventure_sheet_id, :spell_id, :storage_type],
              unique: true, name: "idx_adv_sheet_spells_unique"
  end
end
