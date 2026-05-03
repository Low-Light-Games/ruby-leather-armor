module Admin
  class StoriesController < BaseController
    before_action :set_story, only: [:show, :update, :destroy]

    # GET /admin/stories — server-rendered story list
    def index
      @stories = Story.kept.order(created_at: :desc)
    end

    # GET /admin/stories/new — SPA mount for creating a new story
    def new
      render layout: 'admin'
    end

    # GET /admin/stories/:id — SPA mount for editing a story
    #   HTML: serves SPA shell
    #   JSON: returns story data for the React editor
    def show
      respond_to do |format|
        format.html { render layout: 'admin' }
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
        :title, :preview, :premise, :initial_summary,
        initial_contexts: {},
        story_locations_attributes: [:id, :name, :description, :starting, :_destroy],
        encounter_tables_attributes: [
          :id, :name, :description, :check_frequency_hours, :encounter_chance, :_destroy,
          encounter_table_entries_attributes: [
            :id, :title, :description, :entry_type, :weight, :terrain_types,
            :min_party_level, :max_party_level, :_destroy,
            creature_manifest: [:bestiary_entry_id, :count, :display_name]
          ]
        ],
        story_npcs_attributes: [
          :id, :source, :name, :role, :location_id, :description,
          :knowledge, :attitude, :secret, :_destroy
        ],
        story_clues_attributes: [
          :id, :source, :title, :description, :discovery_method, :location_id,
          :npc_id, :reveals_secret, :difficulty, :_destroy,
          prerequisite_clue_ids: []
        ],
        story_milestones_attributes: [
          :id, :source, :title, :description, :consequence, :_destroy,
          trigger_clue_ids: []
        ]
      )
    end

    def story_json(story)
      base = story.as_json(only: [:id, :title, :preview, :premise, :initial_summary, :initial_contexts, :created_at, :updated_at])
      base["story_locations"] = story.story_locations.order(:id).map { |loc|
        loc.as_json(only: [:id, :name, :description, :starting])
      }
      base["encounter_tables"] = story.encounter_tables.order(:id).map { |t|
        t.as_json(only: [:id, :name, :description, :check_frequency_hours, :encounter_chance]).merge(
          "encounter_table_entries" => t.encounter_table_entries.order(:id).map { |e|
            e.as_json(only: [:id, :title, :description, :entry_type, :weight, :terrain_types, :min_party_level, :max_party_level, :creature_manifest])
          }
        )
      }
      base["story_npcs"] = story.story_npcs.story_level.order(:id).map { |npc|
        npc.as_json(only: [:id, :source, :name, :role, :location_id, :description, :knowledge, :attitude, :secret])
      }
      base["story_clues"] = story.story_clues.story_level.order(:id).map { |clue|
        clue.as_json(only: [:id, :source, :title, :description, :discovery_method, :location_id, :npc_id, :prerequisite_clue_ids, :reveals_secret, :difficulty])
      }
      base["story_milestones"] = story.story_milestones.order(:id).map { |ms|
        ms.as_json(only: [:id, :source, :title, :description, :trigger_clue_ids, :consequence])
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
