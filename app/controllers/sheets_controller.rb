# frozen_string_literal: true

class SheetsController < ApplicationController
  include SheetJsonSerialization
  include PivotSync

  before_action :set_sheet, only: [:show, :update, :destroy]
  before_action :authorize_sheet, only: [:show, :update, :destroy]

  skip_before_action :require_login, only: [:index]

  def index
    respond_to do |format|
      format.html # renders sheets/index.html.erb (the React SPA)
      format.json do
        return head :unauthorized unless current_user
        @sheets = policy_scope(Sheet)
                    .includes(:sheet_feats, :sheet_spells, :sheet_items)
                    .order(created_at: :desc)
        render json: @sheets.map { |s| sheet_json(s) }
      end
    end
  end

  def create
    feat_data, spell_data, item_data = extract_feat_spell_item_params!
    @sheet = current_user.sheets.build(sheet_params)
    authorize(@sheet)

    if @sheet.save
      sync_feats!(@sheet.sheet_feats, feat_data)
      sync_spells!(@sheet.sheet_spells, spell_data)
      sync_items!(@sheet.sheet_items, item_data)
      @sheet.recompute_derived_stats!
      current_user.update_column(:onboarding_state, "in_progress") if current_user.onboarding_state == "new"
      render json: sheet_json(@sheet.reload), status: :created
    else
      render json: { errors: @sheet.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    render json: sheet_json(@sheet)
  end

  def update
    feat_data, spell_data, item_data = extract_feat_spell_item_params!
    if @sheet.update(sheet_params)
      sync_feats!(@sheet.sheet_feats, feat_data) if feat_data
      sync_spells!(@sheet.sheet_spells, spell_data) if spell_data
      sync_items!(@sheet.sheet_items, item_data) if item_data
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
      :character_class, :subclass, :level,
      currency: [:gold, :silver, :copper, :platinum]
    )
  end

  # Extract feat/spell/item arrays from params before they reach sheet_params.
  # Returns [feat_data, spell_data, item_data] where each is nil if not sent.
  def extract_feat_spell_item_params!
    sheet_data = params[:sheet] || {}

    feat_data = nil
    if sheet_data.key?(:feat_ids)
      feat_data = Array(sheet_data.delete(:feat_ids)).map(&:to_s)
    end

    spell_data = nil
    known = sheet_data.key?(:known_spell_ids) ? Array(sheet_data.delete(:known_spell_ids)).map(&:to_s) : nil
    spellbook = sheet_data.key?(:spellbook_spell_ids) ? Array(sheet_data.delete(:spellbook_spell_ids)).map(&:to_s) : nil
    legacy = sheet_data.key?(:spell_ids) ? Array(sheet_data.delete(:spell_ids)).map(&:to_s) : nil

    if known || spellbook || legacy
      spell_data = { known: known, spellbook: spellbook, legacy: legacy }
    end

    item_data = nil
    if sheet_data.key?(:items)
      item_data = Array(sheet_data.delete(:items)).map do |entry|
        if entry.is_a?(ActionController::Parameters)
          entry.permit(:item_id, :quantity, :equipped, :slot_override).to_h
        else
          entry
        end
      end
    end

    [feat_data, spell_data, item_data]
  end

  def sheet_json(sheet)
    serialize_sheet_json(
      sheet,
      feat_rel:  sheet.sheet_feats,
      spell_rel: sheet.sheet_spells,
      item_rel:  sheet.sheet_items
    )
  end
end
