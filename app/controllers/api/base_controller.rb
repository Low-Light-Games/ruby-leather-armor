# frozen_string_literal: true

# Shared base for service-token authenticated JSON APIs.
# Bypasses session-based authentication (no current_user) and CSRF.
module Api
  class BaseController < ActionController::API
    before_action :require_service_token

    private

    def require_service_token
      header = request.headers["Authorization"].to_s
      presented = header.start_with?("Bearer ") ? header.sub("Bearer ", "") : nil
      expected = ENV["MCP_BEARER_TOKEN"]

      if expected.blank? || presented.blank? || !ActiveSupport::SecurityUtils.secure_compare(presented, expected)
        render json: { error: "unauthorized" }, status: :unauthorized
      end
    end

    def render_not_found(message = "not found")
      render json: { error: message }, status: :not_found
    end

    rescue_from ActiveRecord::RecordNotFound do |e|
      render json: { error: "not_found", detail: e.message }, status: :not_found
    end
  end
end
