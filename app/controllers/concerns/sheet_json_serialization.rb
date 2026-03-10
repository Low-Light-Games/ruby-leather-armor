# frozen_string_literal: true

module SheetJsonSerialization
  extend ActiveSupport::Concern

  private

  # Builds a JSON-ready hash for any sheet-like record, merging feat/spell/item
  # pivot data into the details hash for backward compatibility with the frontend.
  #
  # Accepts the three pivot relations so callers can pass either Sheet or
  # AdventureSheet associations without the concern knowing the difference.
  def serialize_sheet_json(sheet, feat_rel:, spell_rel:, item_rel:)
    base = sheet.as_json

    feats = feat_rel.map { |sf|
      sf.choice ? "#{sf.feat_id}::#{sf.choice}" : sf.feat_id
    }

    known_spells    = spell_rel.where(storage_type: "known").pluck(:spell_id)
    spellbook_spells = spell_rel.where(storage_type: "spellbook").pluck(:spell_id)

    items = item_rel.includes(:item_definition).map { |si|
      {
        itemId: si.item_definition_id,
        quantity: si.quantity,
        equipped: si.equipped,
        slotOverride: si.slot_override,
      }
    }

    details = (base["details"] || {}).dup
    details.merge!(
      "feats"       => feats,
      "knownSpells" => known_spells,
      "spellbook"   => spellbook_spells,
      "items"       => items
    )
    base["details"] = details

    base
  end
end
