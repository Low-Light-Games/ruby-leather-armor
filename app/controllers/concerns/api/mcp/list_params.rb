# frozen_string_literal: true

module Api
  module Mcp
    # Shared `?limit=` and `?since=` parsing for /api/mcp/* index endpoints.
    # Each caller picks its own default/max via clamped_limit(default:, max:).
    module ListParams
      extend ActiveSupport::Concern

      def clamped_limit(default:, max:)
        n = params[:limit].to_i
        return default if n <= 0

        [n, max].min
      end

      def parsed_since
        return nil if params[:since].blank?

        Time.zone.parse(params[:since])
      end
    end
  end
end
