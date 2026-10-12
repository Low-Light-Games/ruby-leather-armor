# frozen_string_literal: true

module PivotSync
  extend ActiveSupport::Concern

  private

  def sync_feats!(feat_relation, feat_entries)
    return unless feat_entries

    feat_relation.destroy_all
    feat_entries.each do |entry|
      pool, feat_id, choice = parse_feat_entry(entry.to_s)
      next unless FeatDefinition.exists?(feat_id)

      feat_relation.create!(feat_id: feat_id, choice: choice, pool: pool)
    end
  end

  # Entries look like "pool_id|feat_id::choice"; the pool prefix and the choice are optional.
  def parse_feat_entry(entry)
    pool = SheetFeat::DEFAULT_POOL
    feat_with_choice = entry
    if entry.include?("|")
      pool_part, rest = entry.split("|", 2)
      pool = pool_part.presence || SheetFeat::DEFAULT_POOL
      feat_with_choice = rest.to_s
    end
    feat_id, choice = feat_with_choice.split("::", 2)
    [pool, feat_id, choice]
  end

  def sync_spells!(spell_relation, spell_data)
    return unless spell_data

    spell_relation.destroy_all
    create_spells!(spell_relation, "known", spell_data[:known] || [])
    create_spells!(spell_relation, "spellbook", spell_data[:spellbook] || [])
  end

  def sync_spells_by_type!(spell_relation, storage_type, spell_ids)
    spell_relation.where(storage_type: storage_type).destroy_all
    create_spells!(spell_relation, storage_type, spell_ids)
  end

  def create_spells!(spell_relation, storage_type, spell_ids)
    spell_ids.each do |spell_id|
      next unless SpellDefinition.exists?(spell_id)

      spell_relation.create!(spell_id: spell_id, storage_type: storage_type)
    end
  end

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
