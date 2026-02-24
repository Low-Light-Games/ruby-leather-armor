class StoriesController < ApplicationController
  def index
    @stories = Story.all.order(:title)
    render json: @stories.as_json(only: [:id, :title, :preview])
  end
end
