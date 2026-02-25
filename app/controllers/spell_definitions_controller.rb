# frozen_string_literal: true

class SpellDefinitionsController < ApplicationController
  # GET /spell_definitions
  # Optional filters: ?school=abjuration  ?class=wizard  ?max_level=1
  def index
    spells = SpellDefinition.all
    spells = spells.by_school(params[:school])                               if params[:school].present?
    spells = spells.for_class(params[:class])                                if params[:class].present?
    spells = spells.for_class_and_max_level(params[:class], params[:max_level].to_i) if params[:class].present? && params[:max_level].present?

    render json: spells
  end

  # GET /spell_definitions/:id
  def show
    spell = SpellDefinition.find(params[:id])
    render json: spell
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Spell not found" }, status: :not_found
  end
end
