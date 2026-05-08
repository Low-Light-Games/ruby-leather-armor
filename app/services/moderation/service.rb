# frozen_string_literal: true

module Moderation
  class Service
    class Result
      attr_reader :flagged, :response_text

      def initialize(flagged:, response_text:)
        @flagged        = flagged
        @response_text  = response_text
      end

      def flagged? = flagged
    end

    EVALUATOR_URL = "#{ENV.fetch('EVALUATOR_URL', 'http://evaluator:3001')}/moderate"

    def self.call(player_input, user:)
      new(player_input, user: user).call
    end

    def initialize(player_input, user:)
      @player_input = player_input
      @user         = user
      @config       = ModerationConfig.instance
    end

    def call
      return Result.new(flagged: false, response_text: nil) unless @config.enabled?

      api_result = call_evaluator!

      if api_result["flagged"] && meaningful_violation?(api_result["categories"])
        handle_flagged!(api_result["categories"])
        Result.new(flagged: true, response_text: @config.default_response)
      else
        Result.new(flagged: false, response_text: nil)
      end
    end

    private

    def call_evaluator!
      uri     = URI(EVALUATOR_URL)
      http    = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = 15
      http.open_timeout = 5

      request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      request.body = { input: @player_input }.to_json

      response = http.request(request)
      body     = JSON.parse(response.body)

      if response.code.to_i >= 400
        raise Ai::Error, "Moderation evaluator failed (HTTP #{response.code}): #{body["error"] || response.body.truncate(200)}"
      end

      body
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::ReadTimeout, Net::OpenTimeout => e
      raise Ai::Error, "Moderation evaluator unreachable: #{e.message}"
    end

    def handle_flagged!(categories)
      ActiveRecord::Base.transaction do
        @user.increment!(:moderation_strikes)

        auto_banned     = should_auto_ban?
        auto_untrusted  = @user.trusted? && auto_banned

        ModerationEvent.create!(
          user:              @user,
          input_excerpt:     @player_input.truncate(200),
          flagged_categories: categories || {},
          strike_number:     @user.moderation_strikes,
          auto_banned:       auto_banned,
          auto_untrusted:    auto_untrusted
        )

        if auto_banned
          @user.update!(banned: true, banned_at: Time.current, trusted: false)
        end
      end
    end

    def meaningful_violation?(categories)
      return false if categories.blank?

      flagged_cats = categories.select { |_cat, flagged| flagged }.keys
      (flagged_cats - @config.ignored_categories).any?
    end

    def should_auto_ban?
      @user.moderation_strikes >= @config.max_strikes
    end
  end
end
