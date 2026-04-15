# frozen_string_literal: true

# Serializes a Sheet or AdventureSheet into the JSON shape expected by the
# frontend SPA.  The pivot relations (feats, spells, items) are passed
# explicitly so the presenter works for both model types without needing to
# know which association names to call.
#
# Usage:
#   SheetPresenter.new(adv_sheet,
#     feat_rel:  adv_sheet.adventure_sheet_feats,
#     spell_rel: adv_sheet.adventure_sheet_spells,
#     item_rel:  adv_sheet.adventure_sheet_items
#   ).as_json
class SheetPresenter
  # @param sheet     [Sheet, AdventureSheet]
  # @param feat_rel  [ActiveRecord::Relation]  feat pivot records
  # @param spell_rel [ActiveRecord::Relation]  spell pivot records
  # @param item_rel  [ActiveRecord::Relation]  item pivot records
  def initialize(sheet, feat_rel:, spell_rel:, item_rel:)
    @sheet     = sheet
    @feat_rel  = feat_rel
    @spell_rel = spell_rel
    @item_rel  = item_rel
  end

  def as_json(_ = nil)
    base    = @sheet.as_json
    details = (base["details"] || {}).dup

    base["active_buffs"] = serialized_active_buffs

    details.merge!(
      "feats"       => serialized_feats,
      "knownSpells" => @spell_rel.where(storage_type: "known").pluck(:spell_id),
      "spellbook"   => @spell_rel.where(storage_type: "spellbook").pluck(:spell_id),
      "items"       => serialized_items
    )
    base["details"] = details
    base
  end

  private

  def serialized_feats
    @feat_rel.map do |sf|
      entry = sf.choice ? "#{sf.feat_id}::#{sf.choice}" : sf.feat_id
      pool  = sf.respond_to?(:pool) ? (sf.pool.presence || SheetFeat::DEFAULT_POOL) : SheetFeat::DEFAULT_POOL
      pool == SheetFeat::DEFAULT_POOL ? entry : "#{pool}|#{entry}"
    end
  end

  def serialized_items
    @item_rel.includes(:item_definition).map do |si|
      {
        itemId:       si.item_definition_id,
        quantity:     si.quantity,
        equipped:     si.equipped,
        slotOverride: si.slot_override,
        definition:   si.item_definition&.as_json,
      }
    end
  end

  def serialized_active_buffs
    current_hours = current_game_hours

    Array(@sheet.try(:active_buffs)).filter_map do |buff|
      next unless buff.is_a?(Hash)

      entry = buff.deep_stringify_keys
      expires_at = entry["expires_at_game_hours"]

      if expires_at.present? && current_hours.present? && expires_at.to_f <= current_hours
        next
      end

      remaining_hours = if expires_at.present? && current_hours.present?
                          [expires_at.to_f - current_hours, 0.0].max
                        end

      entry.merge(
        "remaining_hours" => remaining_hours,
        "duration_label" => duration_label_for(remaining_hours)
      )
    end
  end

  def duration_label_for(remaining_hours)
    return "Sustained" if remaining_hours.nil?

    total_minutes = (remaining_hours * 60).round
    return "Expired" if total_minutes <= 0
    return "#{total_minutes}m remaining" if total_minutes < 60

    hours = total_minutes / 60
    minutes = total_minutes % 60
    return "#{hours}h remaining" if minutes.zero?

    "#{hours}h #{minutes}m remaining"
  end

  def current_game_hours
    adventure = @sheet.try(:adventure)
    return nil unless adventure&.respond_to?(:time_context)

    DungeonMaster::Utilities::GameClock.absolute_hours(adventure.time_context)
  end
end
