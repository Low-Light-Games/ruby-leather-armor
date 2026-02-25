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

  def authorize_sheet
    authorize(@sheet)
  end

  def sheet_params
    params.require(:sheet).permit(:name, :description, :strength, :intelligence, :dexterity, :constitution, :wisdom, :charisma, :race, :racial_bonus_attribute, :character_class, :subclass)
  end
end