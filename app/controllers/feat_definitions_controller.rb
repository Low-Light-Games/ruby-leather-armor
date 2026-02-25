# frozen_string_literal: true

class FeatDefinitionsController < ApplicationController
  # GET /feat_definitions
  # Optional filters: ?category=combat  ?choice_type=skill
  def index
    feats = FeatDefinition.all
    feats = feats.by_category(params[:category]) if params[:category].present?
    feats = feats.parameterised                  if params[:parameterised] == "true"

    render json: feats
  end

  # GET /feat_definitions/:id
  def show
    feat = FeatDefinition.find(params[:id])
    render json: feat
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Feat not found" }, status: :not_found
  end
end
