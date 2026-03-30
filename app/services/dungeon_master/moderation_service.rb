# frozen_string_literal: true

module DungeonMaster
  # Calls the OpenAI moderation API on player input.
  #
  # For non-trusted users this runs synchronously before the pipeline.
  # For trusted users ModerationCheckJob runs it async post-pipeline.
  #
  # If the input is flagged: records a ModerationEvent, increments strikes,
  # and auto-bans or removes trust when the configured thresholds are reached.
  class ModerationService
    CONFIG = YAML.load_file(Rails.root.join("config/moderation.yml"))[Rails.env].freeze

    Result = Struct.new(:flagged, :response_text, keyword_init: true) do
      alias_method :flagged?, :flagged
    end

    def self.call(input, user:)
      new(input, user: user).call
    end

    def initialize(input, user:)
      @input  = input
      @user   = user
      @client = OpenAI::Client.new
    end

    def call
      response = @client.moderations(parameters: { input: @input })
      result   = response.dig("results", 0)
      flagged  = result&.dig("flagged") || false
      categories = flagged ? extract_flagged_categories(result) : {}

      record_strike!(categories) if flagged && @user

      Result.new(flagged: flagged, response_text: CONFIG["response_text"])
    rescue Faraday::Error => e
      Rails.logger.error("[DungeonMaster::ModerationService] API error: #{e.message}")
      Result.new(flagged: false, response_text: nil)
    end

    private

    def extract_flagged_categories(result)
      result.dig("categories")&.select { |_, v| v } || {}
    end

    def record_strike!(categories)
      strike_number  = @user.moderation_strikes + 1
      should_ban     = strike_number >= CONFIG["strikes_before_ban"]
      should_untrust = @user.trusted? && strike_number >= CONFIG["strikes_before_untrust"]

      event = ModerationEvent.create!(
        user:              @user,
        input_excerpt:     @input.to_s.first(CONFIG["max_excerpt_length"]),
        flagged_categories: categories,
        strike_number:     strike_number,
        auto_banned:       should_ban,
        auto_untrusted:    should_untrust
      )

      attrs = { moderation_strikes: strike_number }
      if should_ban
        attrs[:banned]    = true
        attrs[:banned_at] = Time.current
      end
      attrs[:trusted] = false if should_untrust

      @user.update!(attrs)
    end
  end
end
