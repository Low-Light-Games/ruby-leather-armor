# frozen_string_literal: true

module DungeonMaster
  # Runs once at adventure creation to add unique flavor to a story's
  # structured data. Always runs. In Embellish mode it only decorates; in
  # Expand mode it also creates adventure-specific NPC and Clue records.
  # Both modes generate the opening DM narrative message.
  #
  # Produces:
  #   adventure.enriched_world   (JSONB)
  #   adventure.enriched_premise (text)
  #   adventure_messages[0]      (opening DM narrative)
  #   StoryNpc / StoryClue records with adventure_id (Expand mode only)
  class Embellisher
    include TextNormalizer

    def initialize(adventure, user: nil)
      @adventure = adventure
      @story = adventure.story
      @config = DmConfig.instance
      @mode = @config.get("embellisher_mode").presence || "embellish"
      @user = user
    end

    def run
      client = AiClient.new(@config)
      model = @config.get("embellisher_model").presence || @config.model
      log = Logging.new(adventure: @adventure, user: @user, dm_service: "standard")

      system_prompt, user_msg = PromptRenderer.render_with_user_message("embellisher",
        premise: @story.premise,
        locations: location_data,
        npcs: npc_data,
        clues: clue_data,
        mode: @mode,
        traversal_context: @adventure.traversal_context,
        social_context: @adventure.social_context,
        character_name: @adventure.adventure_sheets.first&.name,
        initial_summary: @story.initial_summary,
      )

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        raw_response = client.chat(
          system_prompt: system_prompt,
          user_message: user_msg,
          max_tokens: 2500,
          step_name: "embellisher",
          model: model,
        )

        parsed = client.parse_json(raw_response)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        log.ai_log!(
          "embellisher",
          "Adventure ##{@adventure.id} (#{@mode}): #{@story.premise&.truncate(80)}",
          raw_response, parsed,
          parse_status: client.last_parse_status,
          model_used: client.last_model_used,
          duration_ms: duration_ms,
          usage: client.last_usage
        )

        apply_results(parsed)
      rescue DungeonMaster::AiError, DungeonMaster::TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        status = e.is_a?(DungeonMaster::TokenBudgetExceededError) ? "token_budget_exceeded" : "api_error"
        log.ai_log_error!(
          "embellisher",
          "Adventure ##{@adventure.id} (#{@mode}): #{@story.premise&.truncate(80)}",
          e,
          model_used: client.last_model_used,
          status: status,
          duration_ms: duration_ms,
          usage: client.last_usage
        )
        raise
      end
    end

    private

    def location_data
      @story.story_locations.order(:id).map do |loc|
        { name: loc.name, description: loc.description }
      end
    end

    def npc_data
      StoryNpc.where(story_id: @story.id, adventure_id: nil).order(:id).map do |npc|
        { id: npc.id, name: npc.name, role: npc.role, attitude: npc.attitude, description: npc.description }
      end
    end

    def clue_data
      StoryClue.where(story_id: @story.id, adventure_id: nil).order(:id).map do |clue|
        { id: clue.id, title: clue.title, description: clue.description, discovery_method: clue.discovery_method, difficulty: clue.difficulty }
      end
    end

    def apply_results(parsed)
      @adventure.update!(
        enriched_world: parsed["enriched_world"] || {},
        enriched_premise: present_or(parsed["enriched_premise"], @story.premise),
      )

      if parsed["opening_narrative"].present?
        @adventure.adventure_messages.create!(
          role: "dm",
          content: strip(parsed["opening_narrative"]),
          message_type: "narrative"
        )
      end

      return unless @mode == "expand"

      create_expand_npcs(parsed["new_npcs"] || [])
      create_expand_clues(parsed["new_clues"] || [])
    end

    def create_expand_npcs(raw_npcs)
      location_map = @story.story_locations.index_by(&:name)

      raw_npcs.first(2).each do |raw|
        @adventure.story_npcs.create!(
          story: @story,
          source: "embellisher",
          name: present_or(raw["name"], "Unnamed NPC"),
          role: validated_enum(raw["role"], StoryNpc::ROLES, "bystander"),
          location: location_map[raw["location_name"]],
          description: strip(raw["description"]),
          knowledge: strip(raw["knowledge"]),
          attitude: validated_enum(raw["attitude"], StoryNpc::ATTITUDES, "indifferent"),
          secret: raw["secret"] == true,
        )
      end
    end

    def create_expand_clues(raw_clues)
      location_map = @story.story_locations.index_by(&:name)
      all_npcs = StoryNpc.for_adventure(@adventure).index_by(&:name)

      raw_clues.first(2).each do |raw|
        @adventure.story_clues.create!(
          story: @story,
          source: "embellisher",
          title: present_or(raw["title"], "Untitled Clue"),
          description: present_or(raw["description"], "No description"),
          discovery_method: validated_enum(raw["discovery_method"], StoryClue::DISCOVERY_METHODS, "exploration"),
          location: location_map[raw["location_name"]],
          npc: all_npcs[raw["npc_name"]],
          difficulty: validated_enum(raw["difficulty"], StoryClue::DIFFICULTIES, "moderate"),
          prerequisite_clue_ids: [],
          reveals_secret: strip(raw["reveals_secret"]).presence,
        )
      end
    end

    def validated_enum(value, allowed, fallback)
      allowed.include?(value.to_s) ? value.to_s : fallback
    end
  end
end
