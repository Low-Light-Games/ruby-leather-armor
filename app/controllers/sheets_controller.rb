class SheetsController < ApplicationController
  before_action :set_sheet, only: [:show, :update, :destroy]
  before_action :authorize, only: [:show, :update, :destroy]

  def index
    @sheets = policy_scope(Sheet).order(created_at: :desc)
    render json: @sheets
  end

  def list
    @sheets = policy_scope(Sheet).order(created_at: :desc)
  end

  def create
    @sheet = current_user.sheets.build(sheet_params)
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

  def sheet_params
    params.require(:sheet).permit(:name, :strength, :intelligence, :dexterity, :constitution, :wisdom, :charisma)
  end
end