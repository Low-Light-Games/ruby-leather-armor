# frozen_string_literal: true

class SheetsController < ApplicationController
  before_action :set_sheet, only: [:show, :update, :destroy]
  before_action :authorize_sheet, only: [:show, :update, :destroy]

  skip_before_action :require_login, only: [:index]

  def index
    respond_to do |format|
      format.html # renders sheets/index.html.erb (the React SPA)
      format.json do
        @sheets = policy_scope(Sheet).order(created_at: :desc)
        render json: @sheets
      end
    end
  end

  def create
    @sheet = current_user.sheets.build(sheet_params)
    merge_details!(@sheet)
    authorize(@sheet)

    if @sheet.save
      render json: @sheet, status: :created
    else
      render json: { errors: @sheet.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    render json: @sheet
  end

  def update
    merge_details!(@sheet)
    if @sheet.update(sheet_params)
      render json: @sheet
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

  # Merge feat_ids and spell_ids into the details JSON column
  def merge_details!(sheet)
    sheet_data = params[:sheet] || {}
    details = (sheet.details || {}).dup

    details['feats']  = Array(sheet_data[:feat_ids]).map(&:to_s)  if sheet_data.key?(:feat_ids)
    details['spells'] = Array(sheet_data[:spell_ids]).map(&:to_s) if sheet_data.key?(:spell_ids)

    sheet.details = details
  end
end
