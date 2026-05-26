# frozen_string_literal: true

module Api
  module Mcp
    class AdventuresController < Api::BaseController
      include ListParams

      def index
        scope = Adventure.kept.includes(:story, :user).recently_updated
        scope = scope.for_story(params[:story_id])   if params[:story_id].present?
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
        scope = scope.limit(clamped_limit(default: 25, max: 100))

        render json: scope.map { |a| AdventureSerializer.call(a) }
      end

      def show
        adventure = Adventure.includes(:story, :user, :current_location).find(params[:id])
        render json: AdventureSerializer.call(adventure, verbose: true)
      end
    end
  end
end
