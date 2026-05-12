# frozen_string_literal: true

module Encounters
  class CastResolver
    OVERSPAWN_THRESHOLD = 15

    def self.call(adventure:, intent_text:, ai: nil, log: nil, config: nil, scene_retrieval: nil)
      new(adventure: adventure, intent_text: intent_text, ai: ai, log: log,
          config: config, scene_retrieval: scene_retrieval).call
    end

    def initialize(adventure:, intent_text:, ai: nil, log: nil, config: nil, scene_retrieval: nil)
      @adventure       = adventure
      @intent_text     = intent_text.to_s
      @config          = config || DmConfig.instance
      @ai              = ai || Ai::Client.new(@config)
      @log             = log || Ai::Logging.new(adventure: @adventure, user: @adventure.user, dm_service: "standard")
      @scene_retrieval = scene_retrieval
    end

    # @return [Array<AdventureNpc>]
    def call
      ai_entries = AiCall.run(
        adventure: @adventure, intent_text: @intent_text, ai: @ai, log: @log,
        config: @config, scene_retrieval: @scene_retrieval,
      )
      entry_resolver = EntryResolver.new(adventure: @adventure, ai: @ai, log: @log)
      members = ai_entries.flat_map { |entry| entry_resolver.resolve(entry) }
      log_overspawn!(members) if members.size > OVERSPAWN_THRESHOLD
      log_resolved_roster(ai_entries, members)
      members
    rescue StandardError => e
      @log.report_error(e, context: error_context.with(source: "cast_resolver"))
      raise
    end

    private

    def log_resolved_roster(ai_entries, members)
      @log.play_log!(
        "cast_resolver",
        "CastResolver: AI=#{ai_entries.size} entries -> #{members.size} roster member(s)",
        parsed_response: CastResolverEvents::Resolved.new(
          intent:              @intent_text,
          ai_entries:          ai_entries,
          roster_member_ids:   members.map(&:id),
          roster_member_names: members.map(&:name),
        ).to_h,
      )
    end

    def log_overspawn!(members)
      @log.play_log!(
        "cast_resolver_overspawn",
        "CastResolver: #{members.size} > threshold #{OVERSPAWN_THRESHOLD}",
        parsed_response: CastResolverEvents::Overspawn.new(
          adventure_id: @adventure.id,
          member_count: members.size,
          threshold:    OVERSPAWN_THRESHOLD,
          intent:       @intent_text,
        ).to_h,
      )
      ApplicationErrorReporter.notify(
        RuntimeError.new("CastResolver overspawn: #{members.size} members"),
        context: error_context.with(source: "cast_resolver_overspawn", member_count: members.size),
      )
    end

    def error_context
      Lore::ErrorContext.new(
        step:         "cast_resolver",
        adventure_id: @adventure.id,
        loop_id:      nil,
        source:       "cast_resolver",
      )
    end
  end
end
