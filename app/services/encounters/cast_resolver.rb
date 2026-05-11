# frozen_string_literal: true

module Encounters
  # Single AI step + four-tier deterministic lookup that turns the cast
  # resolver's `[{name, type, count}]` output into a roster of
  # AdventureNpc rows, each with a creature_sheet_id linked to a real
  # CreatureSheet. RollRequest then targets one of those rows by ID
  # — no more name strings on the wire, no more impromptu "Name"
  # creatures.
  #
  # The four tiers (highest-first):
  #   1. Existing AdventureNpc by name (with sheet) — reuse the row.
  #   2. Existing CreatureSheet by name in this adventure — adopt onto
  #      the AdventureNpc (creating one if missing).
  #   3. BestiaryEntry by name (story-scoped first, then public) —
  #      Encounters::CreatureCreation.from_bestiary mints sheet(s).
  #   4. BestiaryEntry by default_for_type — same minting path with
  #      the type's default stat block (lookup cannot miss after
  #      seeds run; a miss is an alarming-but-recoverable Sentry event).
  #
  # Cast resolver creations are written as source: "runtime" so they
  # don't collide with the seed-only `(adventure_id, name)` unique index.
  class CastResolver
    AI_STEP_NAME = "cast_resolver"
    OVERSPAWN_THRESHOLD = 15

    TYPE_ENUM = %w[beast fighter goblinoid spellcaster commoner].freeze
    DEFAULT_TYPE = "fighter"
    DEFAULT_ATTITUDE = "indifferent"

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

    # @return [Array<AdventureNpc>] roster for this turn — one row per
    #   resolved creature instance (count > 1 produces N rows).
    def call
      ai_entries = run_ai_call
      members = ai_entries.flat_map { |entry| resolve_entry(entry) }
      log_overspawn!(members) if members.size > OVERSPAWN_THRESHOLD
      log_resolved_roster(ai_entries, members)
      members
    rescue StandardError => e
      @log.report_error(e, context: error_context.with(source: "cast_resolver"))
      raise
    end

    private

    def run_ai_call
      scene_retrieval = @scene_retrieval || retrieve_scene
      system_prompt = Ai::PromptRenderer.render(
        AI_STEP_NAME,
        intent: @intent_text,
        current_location_name: @adventure.current_location&.name,
        scene_retrieval: scene_retrieval,
      )

      prompt_summary = "CastResolver: \"#{@log.truncate(@intent_text)}\""
      request_body   = { system_prompt: system_prompt, user_message: @intent_text }

      parsed = @log.timed_chat_call(AI_STEP_NAME, prompt_summary, ai: @ai, request_body: request_body) do
        raw = @ai.chat(
          system_prompt: system_prompt,
          user_message:  @intent_text,
          step_name:     AI_STEP_NAME,
          model:         @config.model_for(AI_STEP_NAME),
          reasoning_effort: @config.reasoning_effort_for(AI_STEP_NAME),
        )
        [raw, @ai.parse_json(raw)]
      end

      Array(parsed.is_a?(Hash) ? parsed["cast"] : nil).select { |e| e.is_a?(Hash) }
    end

    def retrieve_scene
      SceneRetrieval::ForResolution.call(
        adventure:   @adventure,
        intent_text: @intent_text,
        ai:          @ai,
        log:         @log,
      )
    end

    def resolve_entry(entry)
      name  = entry["name"].to_s.strip
      type  = entry["type"].to_s.downcase.strip
      type  = DEFAULT_TYPE unless TYPE_ENUM.include?(type)
      count = parse_count(entry["count"])
      return [] if name.empty?

      if count == 1
        reused_or_adopted = reuse_or_adopt_single(name)
        return [reused_or_adopted] if reused_or_adopted
      end

      cold_spawn_from_bestiary(name: name, type: type, count: count)
    end

    def parse_count(raw)
      n = Integer(raw) rescue 1
      n.clamp(1, Encounters::CreatureCreation::MAX_COUNT)
    end

    # Tier 1 + Tier 2 collapsed into a single reuse-or-adopt path. Returns
    # a persisted AdventureNpc with creature_sheet_id, or nil if nothing
    # to reuse (caller falls through to bestiary tiers).
    def reuse_or_adopt_single(name)
      existing_npc = lookup_adventure_npc_by_name(name)
      return existing_npc if existing_npc&.creature_sheet_id

      sheet = lookup_creature_sheet_by_name(name)
      return nil unless sheet

      if existing_npc
        existing_npc.update!(creature_sheet_id: sheet.id) if existing_npc.creature_sheet_id.nil?
        existing_npc
      else
        insert_runtime_npcs([sheet], display_name_override: name).first
      end
    end

    def cold_spawn_from_bestiary(name:, type:, count:)
      bestiary = bestiary_by_name(name) || bestiary_by_default_for_type(type)
      unless bestiary
        @log.play_log!(
          "cast_resolver_unresolved",
          "CastResolver: no bestiary entry for name=#{name.inspect} type=#{type.inspect}",
          parsed_response: { name: name, type: type, count: count, adventure_id: @adventure.id },
        )
        ApplicationErrorReporter.notify(
          RuntimeError.new("CastResolver default lookup miss for type=#{type.inspect}"),
          context: { source: "cast_resolver_unresolved", adventure_id: @adventure.id, name: name, type: type },
        )
        return []
      end

      if bestiary.default_for_type
        @log.play_log!(
          "cast_resolver_default_fallback",
          "CastResolver: default_for_type=#{type} for name=#{name.inspect}",
          parsed_response: { name: name, type: type, count: count, bestiary_entry_id: bestiary.id },
        )
      end

      sheets = Encounters::CreatureCreation.from_bestiary(
        adventure:      @adventure,
        bestiary_entry: bestiary,
        display_name:   name,
        count:          count,
      )
      insert_runtime_npcs(sheets)
    end

    def lookup_adventure_npc_by_name(name)
      AdventureNpc
        .for_adventure(@adventure)
        .where("LOWER(name) = ?", name.downcase)
        .first
    end

    def lookup_creature_sheet_by_name(name)
      @adventure.creature_sheets.where("LOWER(name) = ?", name.downcase).first
    end

    def bestiary_by_name(name)
      BestiaryEntry
        .where(story_id: [@adventure.story_id, nil])
        .find_by("LOWER(name) = ?", name.downcase)
    end

    def bestiary_by_default_for_type(type)
      BestiaryEntry.default_for(type).first
    end

    def insert_runtime_npcs(sheets, display_name_override: nil)
      records = sheets.map do |sheet|
        Lore::NpcRecord.new(
          name:              display_name_override || sheet.name,
          attitude:          DEFAULT_ATTITUDE,
          creature_sheet_id: sheet.id,
        )
      end
      Lore::ApplyNpcs.call(
        adventure:   @adventure,
        log:         @log,
        ai:          @ai,
        npc_records: records,
        source:      "runtime",
      )
    end

    def log_resolved_roster(ai_entries, members)
      @log.play_log!(
        "cast_resolver",
        "CastResolver: AI=#{ai_entries.size} entries -> #{members.size} roster member(s)",
        parsed_response: {
          intent: @intent_text.truncate(160),
          ai_entries: ai_entries,
          roster_member_ids: members.map(&:id),
          roster_member_names: members.map(&:name),
        },
      )
    end

    def log_overspawn!(members)
      @log.play_log!(
        "cast_resolver_overspawn",
        "CastResolver: #{members.size} > threshold #{OVERSPAWN_THRESHOLD}",
        parsed_response: {
          adventure_id: @adventure.id,
          member_count: members.size,
          threshold:    OVERSPAWN_THRESHOLD,
          intent:       @intent_text.truncate(160),
        },
      )
      ApplicationErrorReporter.notify(
        RuntimeError.new("CastResolver overspawn: #{members.size} members"),
        context: { source: "cast_resolver_overspawn", adventure_id: @adventure.id, member_count: members.size },
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
