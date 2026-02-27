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
      params.require(:story).permit(:title, :preview, :premise, :hook, :initial_context, :initial_summary)
    end

    def story_json(story)
      story.as_json(only: [:id, :title, :preview, :premise, :hook, :initial_context, :initial_summary, :created_at, :updated_at])
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
