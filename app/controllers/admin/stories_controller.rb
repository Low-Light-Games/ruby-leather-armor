module Admin
  class StoriesController < ApplicationController
    before_action :require_admin
    before_action :set_story, only: [:show, :update, :destroy]

    # GET /admin/stories — server-rendered story list
    def index
      @stories = Story.kept.order(created_at: :desc)
    end

    # GET /admin/stories/new — SPA mount for creating a new story
    def new
      render layout: 'application'
    end

    # GET /admin/stories/:id — SPA mount for editing a story
    #   HTML: serves SPA shell
    #   JSON: returns story data for the React editor
    def show
      respond_to do |format|
        format.html { render layout: 'application' }
        format.json do
          render json: story_json(@story)
        end
      end
    end

    # POST /admin/stories
    def create
      @story = Story.new(story_params)

      if @story.save
        respond_to do |format|
          format.json { render json: story_json(@story), status: :created }
          format.html { redirect_to admin_story_path(@story) }
        end
      else
        render json: { errors: @story.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH /admin/stories/:id
    def update
      if @story.update(story_params)
        render json: story_json(@story)
      else
        render json: { errors: @story.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /admin/stories/:id (soft-delete)
    def destroy
      @story.discard!
      respond_to do |format|
        format.json { render json: { message: 'Story archived' }, status: :ok }
        format.html { redirect_to admin_stories_path, notice: 'Story archived' }
      end
    end

    private

    def set_story
      @story = Story.kept.find(params[:id])
    end

    def story_params
      params.require(:story).permit(
        :title, :preview, :premise, :hook, :initial_context, :initial_summary,
        story_locations_attributes: [
          :id, :name, :description, :starting, :_destroy,
          connections_from_attributes: [:id, :to_location_id, :distance_miles, :terrain_type, :description, :_destroy]
        ],
        encounter_tables_attributes: [
          :id, :name, :description, :check_frequency_hours, :encounter_chance, :_destroy,
          encounter_table_entries_attributes: [
            :id, :title, :description, :entry_type, :weight, :terrain_types,
            :min_party_level, :max_party_level, :_destroy
          ]
        ]
      )
    end

    def story_json(story)
      base = story.as_json(only: [:id, :title, :preview, :premise, :hook, :initial_context, :initial_summary, :created_at, :updated_at])
      base["story_locations"] = story.story_locations.order(:id).map { |loc|
        loc.as_json(only: [:id, :name, :description, :starting]).merge(
          "connections_from" => loc.connections_from.map { |c|
            c.as_json(only: [:id, :to_location_id, :distance_miles, :terrain_type, :description])
          }
        )
      }
      base["encounter_tables"] = story.encounter_tables.order(:id).map { |t|
        t.as_json(only: [:id, :name, :description, :check_frequency_hours, :encounter_chance]).merge(
          "encounter_table_entries" => t.encounter_table_entries.order(:id).map { |e|
            e.as_json(only: [:id, :title, :description, :entry_type, :weight, :terrain_types, :min_party_level, :max_party_level])
          }
        )
      }
      base
    end

    def require_admin
      unless current_user&.admin?
        respond_to do |format|
          format.json { render json: { error: 'Admin access required' }, status: :forbidden }
          format.html { redirect_to root_path }
        end
      end
    end
  end
end
