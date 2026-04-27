# frozen_string_literal: true

# Adventure-sheet API endpoints for live adventure sheet updates and Playwright test overrides.
class AdventureSheetsController < ApplicationController
  include SheetJsonSerialization
  include PivotSync

  PLAYWRIGHT_SHEET_BODY_KEYS = %w[active_buffs conditions].freeze
  PLAYWRIGHT_TEST_HEADER = 'HTTP_X_PLAYWRIGHT_TEST'
  RAILS_ROUTING_PARAM_KEYS = %w[controller action adventure_id format].freeze
  PLAYWRIGHT_WRAPPER_PARAM_KEYS = %w[adventure_sheet].freeze

  before_action :set_adventure
  before_action :set_adventure_sheet

  # PATCH /adventures/:adventure_id/adventure_sheet
  #
  # Updates the adventure sheet's spell/feat/item selections via pivot tables.
  # Only the owning player can update their adventure sheet.
  def update
    authorize @adventure, :update?

    return render_playwright_override if playwright_sheet_test_only_request?

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
    render json: adventure_sheet_json(@adventure_sheet.reload)
  rescue AdventureSheets::CombatUiActionEconomy::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  # Playwright only: PATCH body may contain only active_buffs and/or conditions for UI tests.
  def apply_playwright_sheet_test_overrides!
    raw = params.to_unsafe_h
    assign_playwright_active_buffs(raw)
    assign_playwright_conditions(raw)
    @adventure_sheet.save!
    @adventure_sheet.recompute_derived_stats!
  end

  def playwright_sheet_test_only_request?
    return false unless Rails.env.playwright? || request.env[PLAYWRIGHT_TEST_HEADER] == '1'

    body_keys = params.to_unsafe_h.keys.map(&:to_s) - RAILS_ROUTING_PARAM_KEYS - ignorable_playwright_wrapper_keys
    return false if body_keys.empty?

    body_keys.all? { |key| PLAYWRIGHT_SHEET_BODY_KEYS.include?(key) }
  end

  def ignorable_playwright_wrapper_keys
    PLAYWRIGHT_WRAPPER_PARAM_KEYS.select do |key|
      value = params[key]
      next true if value.respond_to?(:blank?) && value.blank?

      wrapped_keys = wrapped_param_keys(value)
      wrapped_keys.present? && wrapped_keys.all? { |wrapped_key| PLAYWRIGHT_SHEET_BODY_KEYS.include?(wrapped_key) }
    end
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
      feat_rel: adv_sheet.adventure_sheet_feats,
      spell_rel: adv_sheet.adventure_sheet_spells,
      item_rel: adv_sheet.adventure_sheet_items
    )
  end

  def normalize_skill_ranks_param(raw)
    h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    h.transform_keys(&:to_s).transform_values(&:to_i)
  end

  def render_playwright_override
    apply_playwright_sheet_test_overrides!
    render json: adventure_sheet_json(@adventure_sheet.reload)
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

  def assign_playwright_active_buffs(raw)
    return unless raw.key?('active_buffs')

    @adventure_sheet.active_buffs = DungeonMaster::CoercedMutationArray.coerce(
      raw['active_buffs'], field: 'active_buffs', log: nil
    ).map(&:deep_stringify_keys)
  end

  def assign_playwright_conditions(raw)
    return unless raw.key?('conditions')

    @adventure_sheet.conditions = DungeonMaster::CoercedMutationArray.coerce(
      raw['conditions'], field: 'conditions', log: nil
    ).map(&:to_s)
  end

  def wrapped_param_keys(value)
    return [] unless value.respond_to?(:to_unsafe_h) || value.respond_to?(:to_h)

    if value.respond_to?(:to_unsafe_h)
      value.to_unsafe_h.keys.map(&:to_s)
    else
      value.to_h.keys.map(&:to_s)
    end
  end
end
