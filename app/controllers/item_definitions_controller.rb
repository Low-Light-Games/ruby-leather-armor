# frozen_string_literal: true

class ItemDefinitionsController < ApplicationController
  INDEX_FILTERS = %i[item_type slot category].freeze

  # GET /item_definitions
  # Optional filters: ?item_type=armor  ?slot=shield  ?category=medium
  def index
    return render json: CatalogJsonCache.fetch(ItemDefinition) if index_filters.empty?

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

  private

  def index_filters
    params.slice(*INDEX_FILTERS).compact_blank
  end
end
