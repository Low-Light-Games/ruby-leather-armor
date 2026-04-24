# frozen_string_literal: true

class AdventureSheetsController < ApplicationController
  include SheetJsonSerialization
  include PivotSync

  PLAYWRIGHT_SHEET_BODY_KEYS = %w[active_buffs conditions].freeze
  RAILS_ROUTING_PARAM_KEYS = %w[controller action adventure_id].freeze

  before_action :set_adventure
  before_action :set_adventure_sheet

  # PATCH /adventures/:adventure_id/adventure_sheet
  #
  # Updates the adventure sheet's spell/feat/item selections via pivot tables.
  # Only the owning player can update their adventure sheet.
  def update
    authorize @adventure, :update?

    if playwright_sheet_test_only_request?
      apply_playwright_sheet_test_overrides!
      return render json: adventure_sheet_json(@adventure_sheet.reload)
    end

    skill_ranks_rejected = false

    AdventureSheet.transaction do
      if params.key?(:spellbook)
        spellbook_ids = Array(params[:spellbook]).map(&:to_s)
        sync_spells_by_type!(@adventure_sheet.adventure_sheet_spells, "spellbook", spellbook_ids)
      end

      if params.key?(:known_spells)
        known_ids = Array(params[:known_spells]).map(&:to_s)
        sync_spells_by_type!(@adventure_sheet.adventure_sheet_spells, "known", known_ids)
      end

      if params.key?(:feats)
        feat_entries = Array(params[:feats]).map(&:to_s)
        sync_feats!(@adventure_sheet.adventure_sheet_feats, feat_entries)
      end

      if params.key?(:items)
        item_entries = Array(params[:items]).map { |e|
          e.respond_to?(:to_h) ? e.to_h.with_indifferent_access : e
        }
        sync_items!(@adventure_sheet.adventure_sheet_items, item_entries)
      end

      if params.key?(:skill_ranks) && AdventureSheet.column_names.include?("skill_ranks")
        @adventure_sheet.skill_ranks = normalize_skill_ranks_param(params[:skill_ranks])
        unless @adventure_sheet.save
          skill_ranks_rejected = true
          raise ActiveRecord::Rollback
        end
      end

      @adventure_sheet.recompute_derived_stats!
    end

    if skill_ranks_rejected
      return render json: { errors: @adventure_sheet.errors.full_messages }, status: :unprocessable_entity
    end

    render json: adventure_sheet_json(@adventure_sheet.reload)
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
    render json: adventure_sheet_json(@adventure_sheet.reload)
  rescue AdventureSheets::CombatUiActionEconomy::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  private

  # Playwright only: PATCH body may contain only active_buffs and/or conditions for UI tests.
  def apply_playwright_sheet_test_overrides!
    raw = params.to_unsafe_h
    if raw.key?("active_buffs")
      @adventure_sheet.active_buffs = Array(raw["active_buffs"]).map(&:deep_stringify_keys)
    end
    if raw.key?("conditions")
      @adventure_sheet.conditions = Array(raw["conditions"]).map(&:to_s)
    end
    @adventure_sheet.save!
    @adventure_sheet.recompute_derived_stats!
  end

  def playwright_sheet_test_only_request?
    return false unless Rails.env.playwright?

    body_keys = params.to_unsafe_h.keys.map(&:to_s) - RAILS_ROUTING_PARAM_KEYS
    return false if body_keys.empty?

    body_keys.all? { |key| PLAYWRIGHT_SHEET_BODY_KEYS.include?(key) }
  end

  def set_adventure
    @adventure = Adventure.kept.find(params[:adventure_id])
  end

  def set_adventure_sheet
    @adventure_sheet = @adventure.adventure_sheets.first!
  end

  def adventure_sheet_json(adv_sheet)
    serialize_sheet_json(
      adv_sheet,
      feat_rel:  adv_sheet.adventure_sheet_feats,
      spell_rel: adv_sheet.adventure_sheet_spells,
      item_rel:  adv_sheet.adventure_sheet_items
    )
  end

  def normalize_skill_ranks_param(raw)
    h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    h.transform_keys(&:to_s).transform_values { |v| v.to_i }
  end
end
