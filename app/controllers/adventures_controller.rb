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

    stats   = Adventures::StartingStats.new(sheet)
    max_hp  = stats.starting_hp
    ctx     = Adventures::ContextInitializer.new(story)

    directed_dm = ActiveModel::Type::Boolean.new.cast(params[:directed_dm]) && FeatureFlag.enabled?(:directed_dm)

    start_loc = story.starting_location
    seed = story.initial_contexts || {}

    @adventure = Adventure.new(
      user: current_user,
      story: story,
      dm_mode: "standard",
      directed_dm: directed_dm,
      current_location: start_loc,
      traversal_context: (seed["traversal_context"] || {}).deep_merge(ctx.build_traversal(start_loc)),
      combat_context: seed["combat_context"] || {},
      social_context: seed["social_context"] || {},
      exploration_context: seed["exploration_context"] || {},
      rest_context: seed["rest_context"] || {},
      inventory_context: seed["inventory_context"] || {},
      time_context: ctx.build_time_context,
      story_summary: story.initial_summary
    )

    if @adventure.save
      opening_text = story.initial_context.presence || story.preview
      @adventure.adventure_messages.create!(
        role: "dm",
        content: opening_text,
        message_type: "narrative"
      )

      Adventures::SheetCopier.new(
        @adventure, sheet, max_hp: max_hp, currency: stats.remaining_currency
      ).call

      @adventure.update!(plot_state: {
        "discovered_clues" => [],
        "attempted_clues" => [],
        "reached_milestones" => [],
        "npc_met" => [],
        "npc_attitudes" => {},
        "custom_facts" => [],
      })

      run_embellisher(@adventure)

      @adventure.reload
      render json: adventure_json(@adventure), status: :created
    else
      render json: { errors: @adventure.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /adventures/:id - soft-deletes the adventure
  def destroy
    authorize(@adventure)
    @adventure.discard!
    render json: { message: "Adventure deleted" }, status: :ok
  end

  # PATCH /adventures/:id/update_micro_contexts - admin-only endpoint to update micro contexts
  def update_micro_contexts
    @adventure = Adventure.kept.find(params[:id])
    authorize(@adventure)

    update_params = params.permit(
      traversal_context: {},
      combat_context: {},
      social_context: {},
      exploration_context: {},
      rest_context: {},
      inventory_context: {}
    )

    @adventure.update!(update_params)
    render json: { success: true }
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
      directed_dm: adventure.directed_dm?
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

  def run_embellisher(adventure)
    DungeonMaster::Embellisher.new(adventure, user: current_user).run
  rescue DungeonMaster::AiError, DungeonMaster::TokenBudgetExceededError => e
    Rails.logger.error("[AdventuresController] Embellisher failed: #{e.message}")
  end
end
