# frozen_string_literal: true

module Api
  module Mcp
    class StoriesController < Api::BaseController
      MAX_LIMIT = 100
      DEFAULT_LIMIT = 25

      def index
        scope = Story.kept
        scope = scope.visible_to_players unless ActiveModel::Type::Boolean.new.cast(params[:include_hidden])
        scope = scope.where(id: Adventure.where(user_id: params[:user_id]).select(:story_id)) if params[:user_id].present?
        scope = scope.order(updated_at: :desc).limit(clamped_limit)

        render json: scope.map { |s| serialize(s) }
      end

      def show
        render json: serialize(Story.find(params[:id]), include_text: true)
      end

      private

      def clamped_limit
        n = params[:limit].to_i
        return DEFAULT_LIMIT if n <= 0

        [n, MAX_LIMIT].min
      end

      def serialize(story, include_text: false)
        base = {
          id: story.id,
          title: story.title,
          preview: story.preview,
          world_terrain: story.world_terrain,
          hidden_from_players: story.hidden_from_players,
          discarded_at: story.discarded_at,
          created_at: story.created_at,
          updated_at: story.updated_at
        }
        base.merge!(premise: story.premise, opening_message: story.opening_message) if include_text
        base
      end
    end
  end
end
