class StoriesController < ApplicationController
  def index
    @stories = Story.kept.visible_to_players.order(:title)
    render json: @stories.as_json(only: [:id, :title, :preview])
  end
end
