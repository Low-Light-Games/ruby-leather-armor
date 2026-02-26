# frozen_string_literal: true

class AdventureSheetsController < ApplicationController
  before_action :set_adventure
  before_action :set_adventure_sheet

  # PATCH /adventures/:adventure_id/adventure_sheet
  #
  # Updates the adventure sheet's spell/feat/item selections via pivot tables.
  # Only the owning player can update their adventure sheet.
  def update
    authorize @adventure, :show? # reuse the adventure show policy

    # Spellbook update (wizard)
    if params.key?(:spellbook)
      spellbook_ids = Array(params[:spellbook]).map(&:to_s)
      @adventure_sheet.adventure_sheet_spells.where(storage_type: "spellbook").destroy_all
      spellbook_ids.each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)
        @adventure_sheet.adventure_sheet_spells.create!(spell_id: spell_id, storage_type: "spellbook")
      end
    end

    # Known spells update (spontaneous casters)
    if params.key?(:known_spells)
      known_ids = Array(params[:known_spells]).map(&:to_s)
      @adventure_sheet.adventure_sheet_spells.where(storage_type: "known").destroy_all
      known_ids.each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)
        @adventure_sheet.adventure_sheet_spells.create!(spell_id: spell_id, storage_type: "known")
      end
    end

    # Feats update
    if params.key?(:feats)
      feat_entries = Array(params[:feats]).map(&:to_s)
      @adventure_sheet.adventure_sheet_feats.destroy_all
      feat_entries.each do |entry|
        parts = entry.split("::", 2)
        feat_id = parts[0]
        choice  = parts[1]
        next unless FeatDefinition.exists?(feat_id)
        @adventure_sheet.adventure_sheet_feats.create!(feat_id: feat_id, choice: choice)
      end
    end

    # Items update
    if params.key?(:items)
      item_entries = Array(params[:items])
      @adventure_sheet.adventure_sheet_items.destroy_all
      item_entries.each do |entry|
        entry = entry.to_h.with_indifferent_access if entry.respond_to?(:to_h)
        item_id = entry[:item_id].to_s
        next unless ItemDefinition.exists?(item_id)

        @adventure_sheet.adventure_sheet_items.create!(
          item_definition_id: item_id,
          quantity: (entry[:quantity] || 1).to_i,
          equipped: ActiveModel::Type::Boolean.new.cast(entry[:equipped]),
          slot_override: entry[:slot_override]
        )
      end
    end

    @adventure_sheet.recompute_derived_stats!

    # Build response with pivot data included in details
    render json: adventure_sheet_json(@adventure_sheet.reload)
  end

  private

  def set_adventure
    @adventure = Adventure.find(params[:adventure_id])
  end

  def set_adventure_sheet
    @adventure_sheet = @adventure.adventure_sheets.first!
  end

  def adventure_sheet_json(adv_sheet)
    base = adv_sheet.as_json

    feats = adv_sheet.adventure_sheet_feats.map { |sf|
      sf.choice ? "#{sf.feat_id}::#{sf.choice}" : sf.feat_id
    }

    known_spells = adv_sheet.adventure_sheet_spells.where(storage_type: "known").pluck(:spell_id)
    spellbook_spells = adv_sheet.adventure_sheet_spells.where(storage_type: "spellbook").pluck(:spell_id)

    items = adv_sheet.adventure_sheet_items.includes(:item_definition).map { |si|
      {
        itemId: si.item_definition_id,
        quantity: si.quantity,
        equipped: si.equipped,
        slotOverride: si.slot_override,
      }
    }

    details = (base["details"] || {}).dup
    details["feats"] = feats
    details["knownSpells"] = known_spells
    details["spellbook"] = spellbook_spells
    details["items"] = items
    base["details"] = details

    base
  end
end
