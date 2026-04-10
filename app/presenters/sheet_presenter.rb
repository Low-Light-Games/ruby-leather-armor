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
end
