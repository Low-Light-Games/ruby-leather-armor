class AdventuresController < ApplicationController
  skip_before_action :require_login, only: [:new]

  # GET /adventures/new - serves the SPA page for creating an adventure
  def new
    render layout: 'application'
  end

  # GET /adventures/:id - serves the SPA page OR returns JSON for the API
  def show
    respond_to do |format|
      format.html { render layout: 'application' }
      format.json do
        @adventure = Adventure.find(params[:id])
        render json: adventure_json(@adventure)
      end
    end
  end

  # POST /adventures - API endpoint to create an adventure
  def create
    story = Story.find(params[:story_id])
    initial_state = story.story_states.order(:id).first

    unless initial_state
      return render json: { error: 'This story has no states yet' }, status: :unprocessable_entity
    end

    @adventure = Adventure.new(
      sheet_id: params[:sheet_id],
      story_state: initial_state,
      character_gold: 0,
      character_effects: nil,
      character_items: nil
    )

    if @adventure.save
      render json: adventure_json(@adventure), status: :created
    else
      render json: { errors: @adventure.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def adventure_json(adventure)
    {
      id: adventure.id,
      sheet: adventure.sheet,
      story_state: adventure.story_state,
      story: adventure.story_state.story,
      character_gold: adventure.character_gold,
      character_effects: adventure.character_effects,
      character_items: adventure.character_items
    }
  end
end
