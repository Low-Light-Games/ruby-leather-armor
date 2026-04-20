# frozen_string_literal: true

module Admin
  class AdventuresController < BaseController
    before_action :set_adventure, only: [:show, :update, :reset_context, :update_sheet, :update_story_element, :destroy]

    CONTEXT_FIELDS = %w[traversal combat social exploration rest inventory].freeze

    def index
      @show_discarded = params[:discarded] == "1"
      @adventures = Adventure.admin_index_includes.recently_updated
      @adventures = @show_discarded ? @adventures.discarded : @adventures.kept
      @adventures = @adventures.for_story(params[:story_id]) if params[:story_id].present?
    end

    def destroy
      @adventure.destroy!
      redirect_to admin_adventures_path, notice: "Adventure ##{@adventure.id} permanently deleted."
    end

    def show
      @sheet = @adventure.adventure_sheets.includes(:adventure_sheet_items, :adventure_sheet_feats, :adventure_sheet_spells).first
      @creatures = @adventure.creature_sheets.order(:name)
      @story = @adventure.story
      @locations = @story.story_locations.includes(connections_from: :to_location).order(:name)
      @npcs = StoryNpc.for_adventure(@adventure).includes(:location).order(:name)
      @clues = StoryClue.for_adventure(@adventure).includes(:location, :npc).order(:title)
      @recent_messages = @adventure.adventure_messages.order(created_at: :desc).limit(20)
      @registry_entry_uuids = PlayLog.recent_registry_entry_uuids_for_adventure(@adventure.id, limit: 5)
    end

    def update
      return update_time_context if time_context_update_request?

      return update_context if context_update_request?

      return update_adventure_attributes if adventure_attributes_update_request?

      redirect_to admin_adventure_path(@adventure), alert: "Nothing to update."
    rescue JSON::ParserError
      render_invalid_json_response
    end

    def reset_context
      field = params[:context_field].to_s
      unless CONTEXT_FIELDS.include?(field)
        return redirect_to admin_adventure_path(@adventure), alert: "Unknown context: #{field}"
      end

      @adventure.update!("#{field}_context" => {})
      redirect_to admin_adventure_path(@adventure), notice: "#{field.titleize} context reset to {}."
    end

    def update_sheet
      sheet = @adventure.adventure_sheets.first
      unless sheet
        return redirect_to admin_adventure_path(@adventure), alert: "No character sheet found."
      end

      sheet.update!(sheet_params)
      redirect_to admin_adventure_path(@adventure), notice: "Character sheet updated."
    end

    def update_story_element
      klass, record = resolve_story_element
      unless record
        return redirect_to admin_adventure_path(@adventure), alert: "Record not found."
      end

      record.update!(story_element_params_for(klass))
      redirect_to admin_adventure_path(@adventure), notice: "#{klass.model_name.human} updated."
    end

    private

    def require_admin
      redirect_to root_path, alert: "Unauthorized" unless current_user&.admin?
    end

    def set_adventure
      @adventure = Adventure.find(params[:id])
    end

    def adventure_params
      params.require(:adventure).permit(:current_location_id, :story_summary, :scene_summary, :enriched_premise)
    end

    def sheet_params
      params.require(:sheet).permit(:hp, :max_hp, :strength, :dexterity, :constitution,
                                    :intelligence, :wisdom, :charisma, :level)
    end

    def time_context_update_request?
      params[:time_context_json].present?
    end

    def context_update_request?
      params[:context_field].present?
    end

    def adventure_attributes_update_request?
      params[:adventure].present?
    end

    def update_adventure_attributes
      @adventure.update!(adventure_params)
      redirect_to admin_adventure_path(@adventure), notice: "Adventure updated."
    end

    def render_invalid_json_response
      respond_to do |format|
        format.html { redirect_to admin_adventure_path(@adventure), alert: "Invalid JSON format." }
        format.json { render json: { error: "Invalid JSON format." }, status: :unprocessable_entity }
      end
    end

    def update_context
      field = params[:context_field].to_s
      unless CONTEXT_FIELDS.include?(field)
        respond_to do |format|
          format.html { redirect_to admin_adventure_path(@adventure), alert: "Unknown context: #{field}" }
          format.json { render json: { error: "Unknown context: #{field}" }, status: :unprocessable_entity }
        end
        return
      end

      value = params[:context_value].present? ? JSON.parse(params[:context_value]) : {}
      @adventure.update!("#{field}_context" => value)
      respond_to do |format|
        format.html { redirect_to admin_adventure_path(@adventure), notice: "#{field.titleize} context updated." }
        format.json { render json: { context_field: field, context_value: value }, status: :ok }
      end
    end

    def update_time_context
      value = JSON.parse(params[:time_context_json])
      @adventure.update!(time_context: value)
      redirect_to admin_adventure_path(@adventure), notice: "Time context updated."
    end

    def resolve_story_element
      case params[:element_type]
      when "story_location"
        [StoryLocation, @adventure.story.story_locations.find_by(id: params[:element_id])]
      when "story_npc"
        [StoryNpc, StoryNpc.for_adventure(@adventure).find_by(id: params[:element_id])]
      when "story_clue"
        [StoryClue, StoryClue.for_adventure(@adventure).find_by(id: params[:element_id])]
      else
        [nil, nil]
      end
    end

    def story_element_params_for(klass)
      case klass.name
      when "StoryLocation"
        params.require(:element).permit(:name, :description, :starting)
      when "StoryNpc"
        params.require(:element).permit(:name, :role, :attitude, :description, :knowledge, :location_id, :secret)
      when "StoryClue"
        params.require(:element).permit(:title, :description, :discovery_method, :difficulty, :location_id, :npc_id, :reveals_secret)
      else
        {}
      end
    end
  end
end
