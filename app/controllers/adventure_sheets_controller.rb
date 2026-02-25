# frozen_string_literal: true

class AdventureSheetsController < ApplicationController
  before_action :set_adventure
  before_action :set_adventure_sheet

  # PATCH /adventures/:adventure_id/adventure_sheet
  #
  # Updates the adventure sheet's details (spellbook, known spells, etc.).
  # Only the owning player can update their adventure sheet.
  def update
    authorize @adventure, :show? # reuse the adventure show policy

    details = (@adventure_sheet.details || {}).dup

    # Spellbook update (wizard)
    if params[:spellbook].present?
      details["spellbook"] = Array(params[:spellbook]).map(&:to_s)
      details.delete("spells") # clean up legacy
    end

    # Known spells update (spontaneous casters)
    if params[:known_spells].present?
      details["knownSpells"] = Array(params[:known_spells]).map(&:to_s)
      details.delete("spells")
    end

    @adventure_sheet.update!(details: details)

    render json: @adventure_sheet.as_json
  end

  private

  def set_adventure
    @adventure = Adventure.find(params[:adventure_id])
  end

  def set_adventure_sheet
    @adventure_sheet = @adventure.adventure_sheets.first!
  end
end
