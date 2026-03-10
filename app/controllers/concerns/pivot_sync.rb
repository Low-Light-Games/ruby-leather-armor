# frozen_string_literal: true

# Shared destroy-and-recreate logic for feat, spell, and item pivot tables.
# Works with both Sheet and AdventureSheet associations — callers pass the
# relevant relation directly (e.g. sheet.sheet_feats or adv_sheet.adventure_sheet_feats).
module PivotSync
  extend ActiveSupport::Concern

  private

  # Replace all feats on the given relation.
  # Entries may be compound ("feat_id::choice") or simple ("feat_id").
  def sync_feats!(feat_relation, feat_entries)
    return unless feat_entries

    feat_relation.destroy_all
    feat_entries.each do |entry|
      parts   = entry.split("::", 2)
      feat_id = parts[0]
      choice  = parts[1]
      next unless FeatDefinition.exists?(feat_id)

      feat_relation.create!(feat_id: feat_id, choice: choice)
    end
  end

  # Replace all spells on the given relation.
  # spell_data is a hash with optional :known, :spellbook, and :legacy arrays.
  def sync_spells!(spell_relation, spell_data)
    return unless spell_data

    spell_relation.destroy_all

    (spell_data[:known] || []).each do |spell_id|
      next unless SpellDefinition.exists?(spell_id)
      spell_relation.create!(spell_id: spell_id, storage_type: "known")
    end

    (spell_data[:spellbook] || []).each do |spell_id|
      next unless SpellDefinition.exists?(spell_id)
      spell_relation.create!(spell_id: spell_id, storage_type: "spellbook")
    end

    if spell_data[:legacy] && !spell_data[:known] && !spell_data[:spellbook]
      (spell_data[:legacy] || []).each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)
        spell_relation.create!(spell_id: spell_id, storage_type: "known")
      end
    end
  end

  # Replace spells of a single storage type (e.g. "spellbook" or "known").
  # Useful for granular updates like AdventureSheetsController#update.
  def sync_spells_by_type!(spell_relation, storage_type, spell_ids)
    spell_relation.where(storage_type: storage_type).destroy_all
    spell_ids.each do |spell_id|
      next unless SpellDefinition.exists?(spell_id)
      spell_relation.create!(spell_id: spell_id, storage_type: storage_type)
    end
  end

  # Replace all items on the given relation.
  # Each entry: { item_id: "chain_shirt", quantity: 1, equipped: true, slot_override: nil }
  def sync_items!(item_relation, item_entries)
    return unless item_entries

    item_relation.destroy_all
    item_entries.each do |entry|
      entry = entry.to_h.with_indifferent_access if entry.respond_to?(:to_h)
      item_id = entry[:item_id].to_s
      next unless ItemDefinition.exists?(item_id)

      item_relation.create!(
        item_definition_id: item_id,
        quantity: (entry[:quantity] || 1).to_i,
        equipped: ActiveModel::Type::Boolean.new.cast(entry[:equipped]),
        slot_override: entry[:slot_override]
      )
    end
  end
end
