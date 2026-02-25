# frozen_string_literal: true

class SheetsController < ApplicationController
  before_action :set_sheet, only: [:show, :update, :destroy]
  before_action :authorize_sheet, only: [:show, :update, :destroy]

  skip_before_action :require_login, only: [:index]

  def index
    respond_to do |format|
      format.html # renders sheets/index.html.erb (the React SPA)
      format.json do
        @sheets = policy_scope(Sheet)
                    .includes(:sheet_feats, :sheet_spells)
                    .order(created_at: :desc)
        render json: @sheets.map { |s| sheet_json(s) }
      end
    end
  end

  def create
    feat_data, spell_data = extract_feat_spell_params!
    @sheet = current_user.sheets.build(sheet_params)
    authorize(@sheet)

    if @sheet.save
      sync_feats!(@sheet, feat_data)
      sync_spells!(@sheet, spell_data)
      @sheet.recompute_derived_stats!
      render json: sheet_json(@sheet.reload), status: :created
    else
      render json: { errors: @sheet.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    render json: sheet_json(@sheet)
  end

  def update
    feat_data, spell_data = extract_feat_spell_params!
    if @sheet.update(sheet_params)
      sync_feats!(@sheet, feat_data) if feat_data
      sync_spells!(@sheet, spell_data) if spell_data
      @sheet.recompute_derived_stats!
      render json: sheet_json(@sheet.reload)
    else
      render json: { errors: @sheet.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @sheet.destroy
    head :no_content
  end

  private

  def set_sheet
    @sheet = Sheet.find(params[:id])
  end

  def authorize_sheet
    authorize(@sheet)
  end

  def sheet_params
    params.require(:sheet).permit(
      :name, :description, :strength, :intelligence, :dexterity,
      :constitution, :wisdom, :charisma, :race, :racial_bonus_attribute,
      :character_class, :subclass, :level
    )
  end

  # Extract feat/spell arrays from params before they reach sheet_params.
  # Returns [feat_data, spell_data] where each is nil if not sent (no update
  # intended) or an array of entries to sync.
  def extract_feat_spell_params!
    sheet_data = params[:sheet] || {}

    feat_data = nil
    if sheet_data.key?(:feat_ids)
      feat_data = Array(sheet_data.delete(:feat_ids)).map(&:to_s)
    end

    spell_data = nil
    # Spontaneous (known spells)
    known = sheet_data.key?(:known_spell_ids) ? Array(sheet_data.delete(:known_spell_ids)).map(&:to_s) : nil
    # Spellbook
    spellbook = sheet_data.key?(:spellbook_spell_ids) ? Array(sheet_data.delete(:spellbook_spell_ids)).map(&:to_s) : nil
    # Legacy
    legacy = sheet_data.key?(:spell_ids) ? Array(sheet_data.delete(:spell_ids)).map(&:to_s) : nil

    if known || spellbook || legacy
      spell_data = { known: known, spellbook: spellbook, legacy: legacy }
    end

    [feat_data, spell_data]
  end

  # Replace all feats for a sheet with the given entries.
  # Entries may be compound ("feat_id::choice") or simple ("feat_id").
  def sync_feats!(sheet, feat_entries)
    return unless feat_entries

    sheet.sheet_feats.destroy_all
    feat_entries.each do |entry|
      parts = entry.split("::", 2)
      feat_id = parts[0]
      choice  = parts[1]
      next unless FeatDefinition.exists?(feat_id)

      sheet.sheet_feats.create!(feat_id: feat_id, choice: choice)
    end
  end

  # Replace all spells for a sheet with the given spell data.
  def sync_spells!(sheet, spell_data)
    return unless spell_data

    sheet.sheet_spells.destroy_all

    (spell_data[:known] || []).each do |spell_id|
      next unless SpellDefinition.exists?(spell_id)
      sheet.sheet_spells.create!(spell_id: spell_id, storage_type: "known")
    end

    (spell_data[:spellbook] || []).each do |spell_id|
      next unless SpellDefinition.exists?(spell_id)
      sheet.sheet_spells.create!(spell_id: spell_id, storage_type: "spellbook")
    end

    # Legacy support
    if spell_data[:legacy] && !spell_data[:known] && !spell_data[:spellbook]
      (spell_data[:legacy] || []).each do |spell_id|
        next unless SpellDefinition.exists?(spell_id)
        sheet.sheet_spells.create!(spell_id: spell_id, storage_type: "known")
      end
    end
  end

  # Build a JSON-ready hash for a sheet, including feat/spell data from pivots.
  def sheet_json(sheet)
    base = sheet.as_json

    # Build feats array (compound entries for parameterised feats)
    feats = sheet.sheet_feats.map { |sf|
      sf.choice ? "#{sf.feat_id}::#{sf.choice}" : sf.feat_id
    }

    # Build spells by storage type
    known_spells = sheet.sheet_spells.where(storage_type: "known").pluck(:spell_id)
    spellbook_spells = sheet.sheet_spells.where(storage_type: "spellbook").pluck(:spell_id)

    # Merge into the details hash for backward compatibility with frontend
    details = (base["details"] || {}).dup
    details["feats"] = feats
    details["knownSpells"] = known_spells
    details["spellbook"] = spellbook_spells
    base["details"] = details

    base
  end
end
