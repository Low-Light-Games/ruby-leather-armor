# frozen_string_literal: true

module DungeonMaster
  # Calls the Node evaluator's /moderate endpoint to classify player input
  # using the OpenAI Moderation API, then records the result and applies
  # any user-level consequences (strike increment, auto-ban, trust revocation).
  #
  # Used in two modes:
  #   Blocking  — called inline in DungeonMasterService#execute_prompt for regular users.
  #               If flagged, the pipeline is short-circuited and a default response returned.
  #   Async     — enqueued as ModerationCheckJob for trusted users so the pipeline
  #               proceeds without waiting. Strikes and bans still apply after the fact.
  #
  # Usage:
  #   result = DungeonMaster::ModerationService.call(player_input, user: user)
  #   result.flagged?       # => true / false
  #   result.response_text  # => default_response string (only meaningful when flagged)
  class ModerationService
    Result = Struct.new(:flagged, :response_text, keyword_init: true) do
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

      if api_result["flagged"]
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
        raise AiError, "Moderation evaluator failed (HTTP #{response.code}): #{body["error"] || response.body.truncate(200)}"
      end

      body
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::ReadTimeout, Net::OpenTimeout => e
      raise AiError, "Moderation evaluator unreachable: #{e.message}"
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

    def should_auto_ban?
      @user.moderation_strikes >= @config.max_strikes
    end
  end
end
