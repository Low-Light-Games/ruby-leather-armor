module Admin
  class StoriesController < BaseController
    before_action :set_story, only: [:show, :update, :destroy, :generate_npc_sheet]

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
        extract_seed_facts!(@story)
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
      ActiveRecord::Base.transaction do
        unless @story.update(story_params)
          render json: { errors: @story.errors.full_messages }, status: :unprocessable_entity
          raise ActiveRecord::Rollback
        end

        missing = named_story_npcs_missing_bestiary(@story)
        if missing.any?
          render json: {
            errors: missing.map { |npc| "StoryNpc #{npc.name.presence || "##{npc.id}"} has no bestiary entry — generate one before saving." }
          }, status: :unprocessable_entity
          raise ActiveRecord::Rollback
        end

        if @story.saved_change_to_premise? || @story.saved_change_to_opening_message?
          extract_seed_facts!(@story)
        end
        render json: story_json(@story)
      end
    end

    # POST /admin/stories/:id/generate_npc_sheet
    def generate_npc_sheet
      story_npc = @story.story_npcs.find(params.require(:story_npc_id))
      attrs = Authoring::AuthorStoryNpcSheet.call(story_npc: story_npc, user: current_user)

      bestiary = story_npc.bestiary_entry || BestiaryEntry.new(
        id:       SecureRandom.uuid,
        story_id: @story.id,
        source:   "ai-draft"
      )
      bestiary.assign_attributes(attrs)
      bestiary.save!

      story_npc.update!(bestiary_entry_id: bestiary.id) if story_npc.bestiary_entry_id.nil?

      render json: bestiary_entry_json(bestiary.reload)
    rescue ActiveRecord::RecordNotFound => e
      render json: { errors: [e.message] }, status: :not_found
    rescue Ai::Error, StandardError => e
      ApplicationErrorReporter.notify(e, context: { source: "admin_stories_generate_npc_sheet", story_id: @story.id, story_npc_id: params[:story_npc_id] })
      render json: { errors: ["Generation failed: #{e.class}"] }, status: :unprocessable_entity
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
        :title, :preview, :premise, :opening_message, :world_terrain,
        seed_facts: [[:text, :kind, :polarity, { entities: [] }]],
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
          :knowledge, :attitude, :secret, :_destroy,
          { bestiary_entry_attributes: [
            :id, :name, :creature_type, :cr, :alignment, :size,
            :strength, :dexterity, :constitution, :intelligence, :wisdom, :charisma,
            :hp_formula, :ac, :base_attack, :speed, :description, :source
          ] }
        ]
      )
    end

    def named_story_npcs_missing_bestiary(story)
      story.story_npcs.story_level.where(bestiary_entry_id: nil).reject do |npc|
        npc.name.to_s.strip.empty?
      end
    end

    def bestiary_entry_json(entry)
      entry.as_json(only: [
        :id, :name, :creature_type, :cr, :alignment, :size,
        :strength, :dexterity, :constitution, :intelligence, :wisdom, :charisma,
        :hp_formula, :ac, :base_attack, :speed, :description, :source
      ])
    end

    def extract_seed_facts!(story)
      facts = Authoring::ExtractPremise.call(story: story, user: current_user)
      story.update_column(:seed_facts, facts) if facts.is_a?(Array)
    rescue StandardError => e
      ApplicationErrorReporter.notify(e, context: { source: "admin_stories_extract_from_premise", story_id: story.id })
    end

    def story_json(story)
      base = story.as_json(only: [
        :id, :title, :preview, :premise, :opening_message, :world_terrain,
        :seed_facts, :created_at, :updated_at
      ])
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
      base["story_npcs"] = story.story_npcs.story_level.includes(:bestiary_entry).order(:id).map { |npc|
        json = npc.as_json(only: [:id, :source, :name, :role, :location_id, :description, :knowledge, :attitude, :secret])
        json["bestiary_entry"] = npc.bestiary_entry ? bestiary_entry_json(npc.bestiary_entry) : nil
        json
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
