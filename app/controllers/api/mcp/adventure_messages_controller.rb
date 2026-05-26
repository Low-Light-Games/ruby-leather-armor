# frozen_string_literal: true

module Api
  module Mcp
    class AdventureMessagesController < Api::BaseController
      include ListParams

      def index
        scope = AdventureMessage
                  .where(adventure_id: params[:adventure_id])
                  .chronological
                  .created_since(params[:since])
                  .limit(clamped_limit(default: 50, max: 200))

        render json: scope.map { |m| AdventureMessageSerializer.call(m) }
      end

      def show
        render json: AdventureMessageSerializer.call(AdventureMessage.find(params[:id]), verbose: true)
      end
    end
  end
end
