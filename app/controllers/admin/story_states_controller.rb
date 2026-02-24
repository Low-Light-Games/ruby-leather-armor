module Admin
  class StoryStatesController < ApplicationController
    before_action :require_admin
    before_action :set_story
    before_action :set_story_state, only: [:update, :destroy, :reorder]

    # POST /admin/stories/:story_id/story_states
    def create
      max_position = @story.story_states.maximum(:position) || -1
      @state = @story.story_states.build(story_state_params)
      @state.position = max_position + 1

      if @state.save
        render json: state_json(@state), status: :created
      else
        render json: { errors: @state.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH /admin/stories/:story_id/story_states/:id
    def update
      if @state.update(story_state_params)
        render json: state_json(@state)
      else
        render json: { errors: @state.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /admin/stories/:story_id/story_states/:id (soft-delete)
    def destroy
      @state.discard!
      render json: { message: 'Story state archived' }, status: :ok
    end

    # PATCH /admin/stories/:story_id/story_states/:id/reorder
    def reorder
      new_position = params[:position].to_i

      ActiveRecord::Base.transaction do
        old_position = @state.position

        if new_position > old_position
          # Moving down: shift items in between up
          @story.story_states
            .where(position: (old_position + 1)..new_position)
            .where.not(id: @state.id)
            .update_all('position = position - 1')
        elsif new_position < old_position
          # Moving up: shift items in between down
          @story.story_states
            .where(position: new_position..(old_position - 1))
            .where.not(id: @state.id)
            .update_all('position = position + 1')
        end

        @state.update!(position: new_position)
      end

      # Return all states in new order
      states = @story.story_states.kept.order(position: :asc)
      render json: states.map { |s| state_json(s) }
    end

    private

    def set_story
      @story = Story.kept.find(params[:story_id])
    end

    def set_story_state
      @state = @story.story_states.kept.find(params[:id])
    end

    def story_state_params
      params.require(:story_state).permit(:description)
    end

    def state_json(state)
      {
        id: state.id,
        description: state.description,
        position: state.position,
        created_at: state.created_at,
        updated_at: state.updated_at
      }
    end

    def require_admin
      unless current_user&.admin?
        render json: { error: 'Admin access required' }, status: :forbidden
      end
    end
  end
end
