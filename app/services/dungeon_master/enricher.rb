# frozen_string_literal: true

module DungeonMaster
  # Parses an admin's story premise into structured StoryNpc, StoryClue,
  # and StoryMilestone records. Returns proposed records as hashes —
  # the admin reviews and saves them through the normal story editor flow.
  class Enricher
    include TextNormalizer

    def initialize(story, user: nil)
      @story = story
      @config = DmConfig.instance
      @user = user
    end

    # Returns a hash of proposed records: { npcs: [...], clues: [...], milestones: [...] }
    # Does NOT persist anything to the database.
    def enrich
      client = AiClient.new(@config)
      model = @config.get("enricher_model").presence || @config.model
      log = Logging.new(adventure: nil, user: @user, dm_service: "standard")

      system_prompt, user_msg = PromptRenderer.render_with_user_message("enricher",
        premise: @story.premise,
        locations: location_data,
        existing_npcs: existing_npc_data,
        existing_clues: existing_clue_data,
        existing_milestones: existing_milestone_data,
        encounter_entries: encounter_entry_data,
        bestiary_catalog: bestiary_catalog,
        has_encounter_tables: @story.encounter_tables.exists?,
        initial_summary: @story.initial_summary,
      )

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        raw_response = client.chat(
          system_prompt: system_prompt,
          user_message: user_msg,
          max_tokens: 2000,
          step_name: "enricher",
          model: model,
        )

        parsed = client.parse_json(raw_response)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        log.ai_log!(
          "enricher",
          "Story ##{@story.id}: #{@story.premise&.truncate(80)}",
          raw_response, parsed,
          parse_status: client.last_parse_status,
          model_used: client.last_model_used,
          duration_ms: duration_ms,
          usage: client.last_usage
        )

        build_proposed_records(parsed)
      rescue DungeonMaster::AiError, DungeonMaster::TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        status = e.is_a?(DungeonMaster::TokenBudgetExceededError) ? "token_budget_exceeded" : "api_error"
        log.ai_log_error!(
          "enricher",
          "Story ##{@story.id}: #{@story.premise&.truncate(80)}",
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

    def existing_npc_data
      @story.story_npcs.story_level.manual_source.map do |npc|
        { name: npc.name, role: npc.role }
      end
    end

    def existing_clue_data
      @story.story_clues.story_level.manual_source.map do |clue|
        { title: clue.title }
      end
    end

    def existing_milestone_data
      @story.story_milestones.manual_source.map do |ms|
        { title: ms.title }
      end
    end

    def encounter_entry_data
      @story.encounter_tables.flat_map do |table|
        table.encounter_table_entries.map do |entry|
          { title: entry.title, description: entry.description, table_name: table.name }
        end
      end
    end

    def bestiary_catalog
      return [] unless defined?(BestiaryEntry)
      BestiaryEntry.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    end

    def build_proposed_records(parsed)
      location_map = @story.story_locations.index_by(&:name)

      npcs = (parsed["npcs"] || []).map do |raw_npc|
        {
          source: "enricher",
          name: present_or(raw_npc["name"], "Unnamed NPC"),
          role: validated_enum(raw_npc["role"], StoryNpc::ROLES, "bystander"),
          location_id: location_map[raw_npc["location_name"]]&.id,
          description: strip(raw_npc["description"]),
          knowledge: strip(raw_npc["knowledge"]),
          attitude: validated_enum(raw_npc["attitude"], StoryNpc::ATTITUDES, "indifferent"),
          secret: raw_npc["secret"] == true,
        }
      end

      npc_name_map = npcs.each_with_index.to_h { |npc, i| [npc[:name], i] }

      clues = (parsed["clues"] || []).map do |raw_clue|
        {
          source: "enricher",
          title: present_or(raw_clue["title"], "Untitled Clue"),
          description: strip(raw_clue["description"]),
          discovery_method: validated_enum(raw_clue["discovery_method"], StoryClue::DISCOVERY_METHODS, "exploration"),
          location_id: location_map[raw_clue["location_name"]]&.id,
          npc_name: strip(raw_clue["npc_name"]).presence,
          prerequisite_titles: Array(raw_clue["prerequisite_titles"]).map(&:to_s),
          reveals_secret: strip(raw_clue["reveals_secret"]).presence,
          difficulty: validated_enum(raw_clue["difficulty"], StoryClue::DIFFICULTIES, "moderate"),
        }
      end

      milestones = (parsed["milestones"] || []).map do |raw_ms|
        {
          source: "enricher",
          title: present_or(raw_ms["title"], "Untitled Milestone"),
          description: strip(raw_ms["description"]),
          trigger_titles: Array(raw_ms["trigger_titles"]).map(&:to_s),
          consequence: strip(raw_ms["consequence"]),
        }
      end

      encounter_manifests = (parsed["encounter_manifests"] || []).map do |raw_em|
        {
          encounter_entry_title: strip(raw_em["encounter_entry_title"]),
          creatures: Array(raw_em["creatures"]).map do |c|
            {
              bestiary_entry_id: c["bestiary_entry_id"],
              count: (c["count"] || 1).to_i,
              display_name: present_or(c["display_name"], "Creature"),
            }
          end
        }
      end

      proposed_encounter_tables = (parsed["proposed_encounter_tables"] || []).map do |raw_table|
        {
          name: present_or(raw_table["name"], "Encounters"),
          encounter_chance: (raw_table["encounter_chance"] || 15).to_i.clamp(0, 100),
          check_frequency_hours: (raw_table["check_frequency_hours"] || 4).to_i.clamp(1, 24),
          entries: Array(raw_table["entries"]).map do |raw_entry|
            {
              title: present_or(raw_entry["title"], "Encounter"),
              description: strip(raw_entry["description"]),
              entry_type: %w[fixed ai_prompt].include?(raw_entry["entry_type"]) ? raw_entry["entry_type"] : "ai_prompt",
              weight: (raw_entry["weight"] || 1).to_i.clamp(1, 10),
              creatures: Array(raw_entry["creatures"]).map do |c|
                {
                  bestiary_entry_id: c["bestiary_entry_id"],
                  count: (c["count"] || 1).to_i,
                  display_name: present_or(c["display_name"], "Creature"),
                }
              end
            }
          end
        }
      end

      {
        npcs: npcs,
        clues: clues,
        milestones: milestones,
        encounter_manifests: encounter_manifests,
        proposed_encounter_tables: proposed_encounter_tables,
        initial_contexts: sanitize_initial_contexts(parsed["initial_contexts"]),
        reasoning: strip(parsed["reasoning"]),
      }
    end

    def validated_enum(value, allowed, fallback)
      allowed.include?(value.to_s) ? value.to_s : fallback
    end

    CONTEXT_KEYS = %w[
      traversal_context combat_context social_context
      exploration_context rest_context inventory_context
    ].freeze

    def sanitize_initial_contexts(raw)
      return {} unless raw.is_a?(Hash)

      raw.slice(*CONTEXT_KEYS).transform_values do |v|
        v.is_a?(Hash) ? v : nil
      end.compact
    end
  end
end
