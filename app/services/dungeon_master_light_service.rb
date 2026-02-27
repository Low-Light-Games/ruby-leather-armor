# frozen_string_literal: true

# Orchestrates the "Light" AI Dungeon Master pipeline.
#
# Key difference from DungeonMasterService: the AI stays dumb and
# narrative-focused. All mechanical tracking (combat, locations, NPC attitudes)
# lives in ActiveRecord models. The AI declares actions and data requests;
# the app resolves them.
#
# Pipeline:
#   1. Sanitize player input (shared with DungeonMasterService)
#   2. Narrative AI call (minimal prompt, returns actions + data_requests)
#   3. Action resolution (in-app: create NPCs, locations, start combat)
#   4. Data resolution (in-app: query models for requested data)
#   5. Feedback AI call (only if data_requests were present)
#   6. Persist messages and update story context
#
class DungeonMasterLightService
  include DungeonMaster::Sanitization

  class AiError < StandardError; end

  def initialize(adventure, user:)
    @adventure = adventure
    @user = user
    @config = DmConfig.instance
    @ai = DungeonMaster::AiClient.new(@config)
    @log = DungeonMaster::Logging.new(adventure: adventure, user: user, dm_service: "light")
  end

  # ----------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------

  def process_player_prompt(player_input)
    player_msg = persist_message(role: "player", content: player_input, message_type: "narrative")
    result_messages = [player_msg]

    begin
      # If combat is active, route to combat service instead of narrative AI
      encounter = @adventure.active_encounter
      if encounter
        return process_combat_action(encounter, player_input, result_messages)
      end

      triage = run_sanitization(player_input)
      rejection_reason = check_sanitization!(player_input, triage)

      if rejection_reason
        rejection = persist_message(
          role: "system",
          content: rejection_reason,
          message_type: "sanitization_fail"
        )
        return { messages: [player_msg, rejection] }
      end

      clean_input = triage[:sanitized_input]

      response = run_narrative_loop(clean_input)

      dm_msg = persist_message(
        role: "dm",
        content: response[:narrative],
        message_type: "narrative"
      )
      result_messages << dm_msg

      if response[:story_summary].present?
        @adventure.update!(story_summary: response[:story_summary])
      end

      if response[:combat_started]
        combat_msg = persist_message(
          role: "system",
          content: "Combat has begun! The encounter will be managed by the combat system.",
          message_type: "narrative"
        )
        result_messages << combat_msg
      end

      if response[:adventure_complete]
        complete_msg = persist_message(
          role: "system",
          content: "The adventure has reached its conclusion.",
          message_type: "adventure_complete"
        )
        result_messages << complete_msg
      end

      { messages: result_messages }

    rescue DungeonMasterService::SanitizationRejected => e
      rejection = persist_message(role: "system", content: e.message, message_type: "sanitization_fail")
      { messages: [player_msg, rejection] }

    rescue DungeonMasterService::AiError, AiError => e
      error_msg = persist_message(
        role: "system",
        content: "The Dungeon Master is momentarily distracted... (#{e.message})",
        message_type: "narrative"
      )
      { messages: [player_msg, error_msg] }
    end
  end

  def process_roll_result(roll_value, roll_description)
    roll_msg = persist_message(
      role: "player",
      content: "🎲 Rolled #{roll_value} for: #{roll_description}",
      message_type: "roll_result",
      metadata: { roll_value: roll_value, roll_description: roll_description }
    )

    result_messages = [roll_msg]

    begin
      response = run_narrative_loop(
        "The player rolled a #{roll_value} for #{roll_description}."
      )

      dm_msg = persist_message(
        role: "dm",
        content: response[:narrative],
        message_type: "narrative"
      )
      result_messages << dm_msg

    rescue DungeonMasterService::AiError, AiError => e
      error_msg = persist_message(
        role: "system",
        content: "The Dungeon Master is momentarily distracted... (#{e.message})",
        message_type: "narrative"
      )
      result_messages << error_msg
    end

    { messages: result_messages }
  end

  private

  # ----------------------------------------------------------------
  # Combat routing
  # ----------------------------------------------------------------

  def process_combat_action(encounter, player_input, result_messages)
    combat = DungeonMasterLight::CombatService.new(@adventure, log: @log)
    result = combat.process_player_action(encounter, player_input)

    recent_messages = @adventure.adventure_messages
                                .where("created_at > ?", 5.seconds.ago)
                                .order(:created_at)

    recent_messages.each { |m| result_messages << m unless result_messages.map(&:id).include?(m.id) }

    if result[:encounter_ended] && result[:narrative_summary]
      summary_response = run_narrative_loop(
        "Combat has ended. Here is what happened: #{result[:narrative_summary]}. " \
        "Continue the story from here."
      )

      dm_msg = persist_message(
        role: "dm",
        content: summary_response[:narrative],
        message_type: "narrative"
      )
      result_messages << dm_msg
    end

    { messages: result_messages }

  rescue => e
    error_msg = persist_message(
      role: "system",
      content: "Combat error: #{e.message}",
      message_type: "narrative"
    )
    { messages: result_messages + [error_msg] }
  end

  # ----------------------------------------------------------------
  # Multi-step narrative loop
  # ----------------------------------------------------------------

  def run_narrative_loop(player_action)
    # Step 1: Narrative AI call
    ai_response = call_narrative_ai(player_action)

    narrative = ai_response["narrative"] || "The Dungeon Master pauses thoughtfully..."
    actions = ai_response["actions"] || []
    data_requests = ai_response["data_requests"] || []
    adventure_complete = ai_response["adventure_complete"] == true

    if actions.any? || data_requests.any?
      action_types = actions.map { |a| a["type"] }.join(", ")
      request_types = data_requests.map { |r| "#{r['type']}:#{r['name'] || r['from']}" }.join(", ")
      @log.dm_log!(
        "AI declared — actions: [#{action_types.presence || 'none'}], " \
        "data_requests: [#{request_types.presence || 'none'}]"
      )
    end

    # Step 2: Resolve actions (creates models, starts combat, etc.)
    action_resolver = DungeonMasterLight::ActionResolver.new(@adventure, log: @log)
    action_resolver.resolve(actions)

    # Step 3: Resolve data requests
    resolved_data = {}
    if data_requests.any?
      data_resolver = DungeonMasterLight::DataResolver.new(@adventure)
      resolved_data = data_resolver.resolve(data_requests)
      @log.dm_log!("Data resolved: #{resolved_data.to_json}")
    end

    # Step 4: Feedback call (only if data was requested)
    if resolved_data.any?
      feedback_response = call_feedback_ai(resolved_data)
      narrative = feedback_response["narrative"] if feedback_response["narrative"].present?
    end

    # Update immediate context with a brief summary
    update_immediate_context(narrative, actions)

    {
      narrative: narrative,
      adventure_complete: adventure_complete,
      combat_started: action_resolver.combat_started,
      story_summary: ai_response["story_summary"]
    }
  end

  # ----------------------------------------------------------------
  # AI calls
  # ----------------------------------------------------------------

  def call_narrative_ai(player_action)
    prompt_summary = "Light DM narrative: \"#{@log.truncate(player_action)}\""
    raw = nil

    system_prompt = DungeonMasterLight::Prompts.narrative_prompt(@adventure)
    request_body = { system_prompt: system_prompt, user_message: player_action }

    raw = @ai.chat(
      system_prompt: system_prompt,
      user_message: player_action,
      max_tokens: 2048
    )

    parsed = @ai.parse_json(raw, fallback_as: :dm_response)
    @log.ai_log!("light_narrative", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)

    parsed
  rescue DungeonMasterService::AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("light_narrative", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    raise
  end

  def call_feedback_ai(resolved_data)
    prompt_summary = "Light DM feedback: #{resolved_data.keys.join(', ')}"
    raw = nil

    system_prompt = DungeonMasterLight::Prompts.feedback_prompt(resolved_data)
    request_body = { system_prompt: system_prompt, user_message: "Continue the narrative with this data." }

    raw = @ai.chat(
      system_prompt: system_prompt,
      user_message: "Continue the narrative with this data.",
      max_tokens: 1024
    )

    parsed = @ai.parse_json(raw, fallback_as: :dm_response)
    @log.ai_log!("light_feedback", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)

    parsed
  rescue DungeonMasterService::AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("light_feedback", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    @log.dm_log!("Feedback call failed: #{e.message} — using original narrative")
    {}
  end

  # ----------------------------------------------------------------
  # Context & message persistence
  # ----------------------------------------------------------------

  def update_immediate_context(narrative, actions)
    action_summary = actions.map { |a| a["type"] }.join(", ") if actions.any?
    context = "Last narrative beat: #{@log.truncate(narrative, length: 300)}"
    context += " | Actions taken: #{action_summary}" if action_summary

    @adventure.update!(immediate_context: context)
  end

  def persist_message(role:, content:, message_type:, metadata: {})
    @adventure.adventure_messages.create!(
      role: role,
      content: content,
      message_type: message_type,
      metadata: metadata
    )
  end
end
