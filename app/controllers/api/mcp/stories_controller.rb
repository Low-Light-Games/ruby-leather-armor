# frozen_string_literal: true

module Api
  module Mcp
    class StoriesController < Api::BaseController
      include ListParams

      def index
        scope = Story.kept
        scope = scope.visible_to_players unless params[:include_hidden] == "1"
        scope = scope.for_user(params[:user_id]) if params[:user_id].present?
        scope = scope.order(updated_at: :desc).limit(clamped_limit(default: 25, max: 100))

        render json: scope.map { |s| StorySerializer.call(s) }
      end

      def show
        render json: StorySerializer.call(Story.find(params[:id]), include_text: true)
      end
    end
  end
end
