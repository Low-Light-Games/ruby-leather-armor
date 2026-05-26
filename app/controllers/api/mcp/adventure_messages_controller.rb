# frozen_string_literal: true

module Api
  module Mcp
    class AdventureMessagesController < Api::BaseController
      MAX_LIMIT = 200
      DEFAULT_LIMIT = 50

      def index
        scope = AdventureMessage.where(adventure_id: params[:adventure_id]).chronological
        scope = scope.where("created_at >= ?", Time.zone.parse(params[:since])) if params[:since].present?
        scope = scope.limit(clamped_limit)

        render json: scope.map { |m| serialize(m) }
      end

      def show
        message = AdventureMessage.find(params[:id])
        render json: serialize(message, verbose: true)
      end

      private

      def clamped_limit
        n = params[:limit].to_i
        return DEFAULT_LIMIT if n <= 0

        [n, MAX_LIMIT].min
      end

      def serialize(message, verbose: false)
        {
          id: message.id,
          adventure_id: message.adventure_id,
          user_id: message.user_id,
          role: message.role,
          message_type: message.message_type,
          content: message.content,
          created_at: message.created_at,
          updated_at: verbose ? message.updated_at : nil
        }.compact
      end
    end
  end
end
