# frozen_string_literal: true

module Api
  module Mcp
    class AdventuresController < Api::BaseController
      MAX_LIMIT = 100
      DEFAULT_LIMIT = 25

      def index
        scope = Adventure.kept.includes(:story, :user).recently_updated
        scope = scope.for_story(params[:story_id]) if params[:story_id].present?
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
        scope = scope.limit(clamped_limit)

        render json: scope.map { |a| serialize(a) }
      end

      def show
        adventure = Adventure.includes(:story, :user, :current_location).find(params[:id])
        render json: serialize(adventure, verbose: true)
      end

      private

      def clamped_limit
        n = params[:limit].to_i
        return DEFAULT_LIMIT if n <= 0

        [n, MAX_LIMIT].min
      end

      def serialize(adventure, verbose: false)
        base = {
          id: adventure.id,
          user_id: adventure.user_id,
          user_email: adventure.user&.email,
          story_id: adventure.story_id,
          story_title: adventure.story&.title,
          discarded_at: adventure.discarded_at,
          ended_at: adventure.ended_at,
          end_reason: adventure.end_reason,
          created_at: adventure.created_at,
          updated_at: adventure.updated_at
        }
        if verbose
          base.merge!(
            current_location: adventure.current_location&.then { |l| { id: l.id, name: l.name } },
            directed_dm: adventure.directed_dm?,
            use_gamemaster_orchestrator: adventure.use_gamemaster_orchestrator?,
            combat_active: adventure.combat_active?
          )
        end
        base
      end
    end
  end
end
