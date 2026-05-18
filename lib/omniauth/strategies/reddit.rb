# frozen_string_literal: true

require "omniauth-oauth2"

module OmniAuth
  module Strategies
    class Reddit < OmniAuth::Strategies::OAuth2
      option :name, "reddit"

      option :client_options, {
        site: "https://www.reddit.com",
        authorize_url: "/api/v1/authorize",
        token_url: "/api/v1/access_token"
      }

      option :authorize_params, { duration: "temporary", scope: "identity" }

      uid { raw_info["id"] }

      info do
        { name: raw_info["name"] }
      end

      def raw_info
        @raw_info ||= access_token.get("https://oauth.reddit.com/api/v1/me").parsed
      end

      def callback_url
        full_host + callback_path
      end
    end
  end
end
