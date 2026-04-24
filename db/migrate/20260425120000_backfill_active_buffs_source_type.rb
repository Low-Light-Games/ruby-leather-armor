# frozen_string_literal: true

# Legacy active_buff rows lacked source_type; buffs_remove now keys on (id, source_type).
# Infer best-effort type from catalog tables so removals and UI stay consistent.
class BackfillActiveBuffsSourceType < ActiveRecord::Migration[7.1]
  def up
    say_with_time "Backfill source_type on adventure_sheets.active_buffs" do
      AdventureSheet.find_each do |sheet|
        buffs = Array(sheet.active_buffs)
        next if buffs.empty?

        new_buffs, changed = normalize_buffs(buffs)
        sheet.update_columns(active_buffs: new_buffs, updated_at: Time.current) if changed
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def normalize_buffs(buffs)
    changed = false
    out = buffs.map do |raw|
      next raw unless raw.is_a?(Hash)

      h = raw.deep_stringify_keys
      if h["source_type"].present?
        h
      else
        changed = true
        sid = h["source"].to_s
        h.merge("source_type" => infer_source_type(sid))
      end
    end
    [out, changed]
  end

  def infer_source_type(source_id)
    return "spell" if SpellDefinition.exists?(id: source_id)

    return "item" if ItemDefinition.exists?(id: source_id)

    return "class_ability" if ClassAbilityDefinition.exists?(id: source_id)

    "spell"
  end
end
