# frozen_string_literal: true

module Admin
  class AdventuresController < ApplicationController
    before_action :require_admin
    before_action :set_adventure, only: [:show, :update, :reset_context, :update_sheet, :update_story_element, :destroy]

    CONTEXT_FIELDS = %w[traversal combat social exploration rest inventory].freeze

    def index
      @show_discarded = params[:discarded] == "1"
      @adventures = Adventure.includes(:user, :story, :current_location, :adventure_sheets)
                             .order(updated_at: :desc)
      @adventures = @show_discarded ? @adventures.discarded : @adventures.kept
      @adventures = @adventures.where(story_id: params[:story_id]) if params[:story_id].present?
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
      @pipeline_run_ids = AiLog.where(adventure_id: @adventure.id)
                               .where.not(pipeline_run_id: nil)
                               .order(created_at: :desc)
                               .pluck(:pipeline_run_id)
                               .uniq
                               .first(5)
    end

    def update
      if params[:time_context_json].present?
        update_time_context
      elsif params[:context_field].present?
        update_context
      elsif params[:adventure].present?
        @adventure.update!(adventure_params)
        redirect_to admin_adventure_path(@adventure), notice: "Adventure updated."
      else
        redirect_to admin_adventure_path(@adventure), alert: "Nothing to update."
      end
    rescue JSON::ParserError
      redirect_to admin_adventure_path(@adventure), alert: "Invalid JSON format."
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

    def update_context
      field = params[:context_field].to_s
      unless CONTEXT_FIELDS.include?(field)
        return redirect_to admin_adventure_path(@adventure), alert: "Unknown context: #{field}"
      end

      value = params[:context_value].present? ? JSON.parse(params[:context_value]) : {}
      @adventure.update!("#{field}_context" => value)
      redirect_to admin_adventure_path(@adventure), notice: "#{field.titleize} context updated."
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
