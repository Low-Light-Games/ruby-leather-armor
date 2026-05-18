# frozen_string_literal: true

require_relative "../../../lib/omniauth/strategies/reddit"

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           ENV["GOOGLE_CLIENT_ID"],
           ENV["GOOGLE_CLIENT_SECRET"],
           {
             scope: "email,profile",
             prompt: "select_account",
             image_aspect_ratio: "square",
             image_size: 50,
             redirect_uri: ENV["GOOGLE_OAUTH_REDIRECT_URI"]
           }

  provider :reddit,
           ENV["REDDIT_CLIENT_ID"],
           ENV["REDDIT_CLIENT_SECRET"],
           redirect_uri: ENV["REDDIT_OAUTH_REDIRECT_URI"]

  provider :discord,
           ENV["DISCORD_CLIENT_ID"],
           ENV["DISCORD_CLIENT_SECRET"],
           scope: "identify email",
           redirect_uri: ENV["DISCORD_OAUTH_REDIRECT_URI"]

  provider :twitchtv,
           ENV["TWITCH_CLIENT_ID"],
           ENV["TWITCH_CLIENT_SECRET"],
           scope: "user:read:email",
           redirect_uri: ENV["TWITCH_OAUTH_REDIRECT_URI"]
end

OmniAuth.config.allowed_request_methods = [:post]
