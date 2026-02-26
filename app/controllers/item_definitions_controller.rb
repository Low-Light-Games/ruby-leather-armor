# frozen_string_literal: true

class ItemDefinitionsController < ApplicationController
  # GET /item_definitions
  # Optional filters: ?item_type=armor  ?slot=shield  ?category=medium
  def index
    items = ItemDefinition.all
    items = items.by_type(params[:item_type]) if params[:item_type].present?
    items = items.by_slot(params[:slot])      if params[:slot].present?
    items = items.where(category: params[:category]) if params[:category].present?

    render json: items
  end

  # GET /item_definitions/:id
  def show
    item = ItemDefinition.find(params[:id])
    render json: item
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Item not found" }, status: :not_found
  end
end
