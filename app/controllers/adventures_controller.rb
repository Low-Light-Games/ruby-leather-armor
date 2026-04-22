# frozen_string_literal: true

class AdventuresController < ApplicationController
  include SheetJsonSerialization

  skip_before_action :require_login, only: [:new]
  before_action :set_adventure, only: [:show, :destroy]

  # GET /adventures/new - serves the SPA page for creating an adventure
  def new
    render layout: "application"
  end

  # GET /adventures - returns the current user's ongoing adventures as JSON
  def index
    adventures = policy_scope(Adventure)
                   .includes(adventure_sheets: [], story: [])
                   .order(updated_at: :desc)

    render json: adventures.map { |a| adventure_summary(a) }
  end

  # GET /adventures/:id - serves the SPA page OR returns JSON for the API
  def show
    authorize(@adventure)

    respond_to do |format|
      format.html { render layout: "application" }
      format.json do
        render json: adventure_json(@adventure)
      end
    end
  end

  # POST /adventures - API endpoint to create an adventure
  def create
    story = Story.kept.find(params[:story_id])
    sheet = policy_scope(Sheet).find(params[:sheet_id])

    directed_dm = ActiveModel::Type::Boolean.new.cast(params.fetch(:directed_dm, false))
    # `users.admin` is nullable: (paid? || admin) can be nil (false || nil => nil)
    # and would violate NOT NULL on adventures.skip_world_sanity_check.
    can_opt_out_world_sanity = current_user.paid? || current_user.admin == true
    skip_world_sanity_check  = !!(can_opt_out_world_sanity &&
      ActiveModel::Type::Boolean.new.cast(params.fetch(:skip_world_sanity_check, true)))

    @adventure = Adventures::Bootstrap.new(
      story:                   story,
      sheet:                   sheet,
      user:                    current_user,
      directed_dm:             directed_dm,
      skip_world_sanity_check: skip_world_sanity_check
    ).call

    render json: adventure_json(@adventure), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # DELETE /adventures/:id - soft-deletes the adventure
  def destroy
    authorize(@adventure)
    @adventure.discard!
    render json: { message: "Adventure deleted" }, status: :ok
  end

  private

  def set_adventure
    @adventure = Adventure.kept.find(params[:id])
  end

  def adventure_summary(adventure)
    adv_sheet = adventure.adventure_sheets.first
    {
      id: adventure.id,
      character_name: adv_sheet&.name || "Unknown",
      story_title: adventure.story.title,
      character_currency: adv_sheet&.currency || { "gold" => 0, "silver" => 0, "copper" => 0, "platinum" => 0 },
      created_at: adventure.created_at,
      updated_at: adventure.updated_at
    }
  end

  def adventure_json(adventure)
    adv_sheet = adventure.adventure_sheets
                         .includes(:adventure_sheet_feats, :adventure_sheet_spells, :adventure_sheet_items)
                         .first
    {
      id: adventure.id,
      adventure_sheet: adventure_sheet_json(adv_sheet),
      story: adventure.story,
      battlefield: DungeonMaster::Battlefield::ApiSnapshot.for_adventure(adventure),
      traversal_context: adventure.traversal_context,
      combat_context: adventure.combat_context,
      social_context: adventure.social_context,
      exploration_context: adventure.exploration_context,
      rest_context: adventure.rest_context,
      inventory_context: adventure.inventory_context,
      time_context: adventure.time_context,
      story_summary: adventure.story_summary,
      scene_summary: adventure.scene_summary,
      current_category: adventure.current_category,
      ended: adventure.ended?,
      ended_at: adventure.ended_at,
      end_reason: adventure.end_reason,
      directed_dm: adventure.directed_dm?,
      skip_world_sanity_check: adventure.skip_world_sanity_check?
    }
  end

  def adventure_sheet_json(adv_sheet)
    return nil unless adv_sheet

    serialize_sheet_json(
      adv_sheet,
      feat_rel:  adv_sheet.adventure_sheet_feats,
      spell_rel: adv_sheet.adventure_sheet_spells,
      item_rel:  adv_sheet.adventure_sheet_items
    )
  end

end
