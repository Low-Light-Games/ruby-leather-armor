# frozen_string_literal: true

# Adventure-sheet API endpoints for live adventure sheet updates.
class AdventureSheetsController < ApplicationController
  include SheetJsonSerialization
  include PivotSync
  include AdventureScoping

  before_action :set_adventure
  before_action :set_adventure_sheet

  # PATCH /adventures/:adventure_id/adventure_sheet
  #
  # Updates the adventure sheet's spell/feat/item selections via pivot tables.
  # Only the owning player can update their adventure sheet.
  def update
    authorize @adventure, :update?
    render_update_result(perform_sheet_update)
  end

  # PATCH /adventures/:adventure_id/adventure_sheet/toggle_equip
  #
  # Toggles the equipped state of a single item on the adventure sheet.
  # Expects { item_id: "warhammer" }.
  def toggle_equip
    authorize @adventure, :update?

    AdventureSheet.transaction do
      if @adventure.combat_active?
        AdventureSheets::CombatUiActionEconomy.apply_equip_toggle!(adventure: @adventure, sheet: @adventure_sheet)
      end

      item = @adventure_sheet.adventure_sheet_items.find_by!(item_definition_id: params[:item_id])
      item.equipped = !item.equipped
      item.save!
      @adventure_sheet.recompute_derived_stats!
    end
    render json: {
      adventure_sheet: adventure_sheet_json(@adventure_sheet.reload),
      combat_context: @adventure.reload.combat_context
    }
  rescue AdventureSheets::CombatUiActionEconomy::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  def set_adventure
    @adventure = adventure_scope.find(params[:adventure_id])
  end

  def set_adventure_sheet
    @adventure_sheet = @adventure.adventure_sheets.first!
  end

  def adventure_sheet_json(adv_sheet)
    serialize_sheet_json(
      adv_sheet,
      feat_rel: adv_sheet.adventure_sheet_feats,
      spell_rel: adv_sheet.adventure_sheet_spells,
      item_rel: adv_sheet.adventure_sheet_items
    )
  end

  def normalize_skill_ranks_param(raw)
    h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    h.transform_keys(&:to_s).transform_values(&:to_i)
  end

  def render_update_result(skill_ranks_rejected)
    if skill_ranks_rejected
      render json: { errors: @adventure_sheet.errors.full_messages }, status: :unprocessable_entity
    else
      render json: adventure_sheet_json(@adventure_sheet.reload)
    end
  end

  def perform_sheet_update
    skill_ranks_rejected = false

    AdventureSheet.transaction do
      sync_spellbook_if_present
      sync_known_spells_if_present
      sync_feats_if_present
      sync_items_if_present
      skill_ranks_rejected = skill_ranks_rejected?
      @adventure_sheet.recompute_derived_stats!
      raise ActiveRecord::Rollback if skill_ranks_rejected
    end

    skill_ranks_rejected
  end

  def sync_spellbook_if_present
    return unless params.key?(:spellbook)

    spellbook_ids = Array(params[:spellbook]).map(&:to_s)
    sync_spells_by_type!(@adventure_sheet.adventure_sheet_spells, 'spellbook', spellbook_ids)
  end

  def sync_known_spells_if_present
    return unless params.key?(:known_spells)

    known_ids = Array(params[:known_spells]).map(&:to_s)
    sync_spells_by_type!(@adventure_sheet.adventure_sheet_spells, 'known', known_ids)
  end

  def sync_feats_if_present
    return unless params.key?(:feats)

    feat_entries = Array(params[:feats]).map(&:to_s)
    sync_feats!(@adventure_sheet.adventure_sheet_feats, feat_entries)
  end

  def sync_items_if_present
    return unless params.key?(:items)

    item_entries = Array(params[:items]).map do |entry|
      entry.respond_to?(:to_h) ? entry.to_h.with_indifferent_access : entry
    end
    sync_items!(@adventure_sheet.adventure_sheet_items, item_entries)
  end

  def skill_ranks_rejected?
    return false unless params.key?(:skill_ranks) && AdventureSheet.column_names.include?('skill_ranks')

    @adventure_sheet.skill_ranks = normalize_skill_ranks_param(params[:skill_ranks])
    !@adventure_sheet.save
  end
end
