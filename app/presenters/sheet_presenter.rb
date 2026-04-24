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
  class SheetDetailsBuilder
    def initialize(base_details:, feats:, spell_rel:, items:)
      @base_details = base_details
      @feats = feats
      @spell_rel = spell_rel
      @items = items
    end

    def to_h
      spell_ids_by_storage_type = grouped_spell_ids
      @base_details.merge(
        "feats" => @feats,
        "knownSpells" => spell_ids_by_storage_type.fetch("known", []),
        "spellbook" => spell_ids_by_storage_type.fetch("spellbook", []),
        "items" => @items
      )
    end

    private

    def grouped_spell_ids
      @spell_rel
        .pluck(:storage_type, :spell_id)
        .each_with_object({}) do |(storage_type, spell_id), grouped_spell_ids|
          grouped_spell_ids[storage_type] ||= []
          grouped_spell_ids[storage_type] << spell_id
        end
    end
  end

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
    serialized_sheet = @sheet.as_json

    serialized_sheet["active_buffs"] = serialized_active_buffs
    details_payload = SheetDetailsBuilder.new(
      base_details: (serialized_sheet["details"] || {}).dup,
      feats: serialized_feats,
      spell_rel: @spell_rel,
      items: serialized_items
    )

    serialized_sheet["details"] = details_payload.to_h
    serialized_sheet
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

      # Client JSON contract: always include source_type (spell | item | class_ability); nil only
      # until legacy rows are backfilled. reverse_merge makes the intent obvious vs merge(self).
      entry.reverse_merge("source_type" => nil).merge(
        "remaining_hours" => remaining_hours,
        "duration_label" => duration_label_for(remaining_hours)
      )
    end
  end

  def duration_label_for(remaining_hours)
    return "Sustained" if remaining_hours.nil?

    total_seconds = (remaining_hours * 3600).round
    return "Expired" if total_seconds <= 0

    if total_seconds < 5.minutes
      minutes = total_seconds / 60
      seconds = total_seconds % 60
      return format("%d:%02d remaining", minutes, seconds)
    end

    total_minutes = (total_seconds / 60.0).round
    return "#{total_minutes} min remaining" if total_minutes < 60

    hours = total_minutes / 60
    minutes = total_minutes % 60
    return "#{hours} hr remaining" if minutes.zero?

    "#{hours} hr #{minutes} min remaining"
  end

  def current_game_hours
    adventure = @sheet.try(:adventure)
    return nil unless adventure&.respond_to?(:time_context)

    DungeonMaster::Utilities::GameClock.absolute_hours(adventure.time_context)
  end
end
