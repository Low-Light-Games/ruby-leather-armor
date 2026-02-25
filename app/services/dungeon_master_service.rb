# frozen_string_literal: true

# Orchestrates the AI Dungeon Master pipeline.
#
# Delegates to:
#   DungeonMaster::Prompts   – system prompt text
#   DungeonMaster::AiClient  – OpenAI transport & JSON parsing
#   DungeonMaster::History   – conversation context builder
#   DungeonMaster::Logging   – DmLog / AiLog persistence
#
class DungeonMasterService
  class SanitizationRejected < StandardError; end
  class AiError < StandardError; end

  def initialize(adventure, user:)
    @adventure = adventure
    @user      = user
    @config    = DmConfig.instance
    @ai        = DungeonMaster::AiClient.new(@config)
    @log       = DungeonMaster::Logging.new(adventure: adventure, user: user)
  end

  # ----------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------

  # Process a player prompt through the 2-call pipeline.
  # Returns { messages: [AdventureMessage, ...] }
  def process_player_prompt(player_input)
    player_msg = persist_message(role: "player", content: player_input, message_type: "narrative")
    result_messages = [player_msg]

    begin
      # --- Call 1: Sanitization ---
      sanitized = sanitize_input(player_input)

      unless sanitized[:safe]
        @log.dm_log!("Message \"#{@log.truncate(player_input)}\" was malicious, and ignored. Reason: #{sanitized[:reason]}")
        rejection = persist_message(
          role: "system",
          content: sanitized[:reason] || "Your input was rejected. Please try a valid in-character action.",
          message_type: "sanitization_fail"
        )
        return { messages: [player_msg, rejection] }
      end

      clean_input = sanitized[:sanitized_input]

      if clean_input != player_input
        @log.dm_log!("Message \"#{@log.truncate(player_input)}\" had to be sanitized. Clean version: \"#{@log.truncate(clean_input)}\"")
      else
        @log.dm_log!("Message \"#{@log.truncate(player_input)}\" passed the sanitization check.")
      end

      # --- Call 2: DM Response ---
      dm_response = generate_dm_response(clean_input)

      log_dm_reasoning(dm_response)

      dm_msg = persist_message(
        role: "dm",
        content: dm_response[:narrative],
        message_type: dm_response[:roll_request].present? ? "roll_request" : "narrative",
        metadata: { roll_request: dm_response[:roll_request] }.compact_blank
      )
      result_messages << dm_msg

      if dm_response[:advance_stage]
        advance_msg = advance_story_stage!
        result_messages << advance_msg if advance_msg
      end

      { messages: result_messages }

    rescue SanitizationRejected => e
      rejection = persist_message(role: "system", content: e.message, message_type: "sanitization_fail")
      { messages: [player_msg, rejection] }

    rescue AiError => e
      error_msg = persist_message(
        role: "system",
        content: "The Dungeon Master is momentarily distracted... (#{e.message})",
        message_type: "narrative"
      )
      { messages: [player_msg, error_msg] }
    end
  end

  # Process a dice roll result submitted by the player.
  def process_roll_result(roll_value, roll_description)
    roll_msg = persist_message(
      role: "player",
      content: "🎲 Rolled #{roll_value} for: #{roll_description}",
      message_type: "roll_result",
      metadata: { roll_value: roll_value, roll_description: roll_description }
    )

    result_messages = [roll_msg]

    begin
      dm_response = generate_dm_response(
        "The player rolled a #{roll_value} for #{roll_description}.",
        call_type: "roll_response"
      )

      reasoning = dm_response[:reasoning] || "No reasoning provided"
      log_parts = ["Roll result #{roll_value} for \"#{roll_description}\". DM reasoning: #{reasoning}"]
      log_parts << "Advance stage: YES" if dm_response[:advance_stage]
      @log.dm_log!(log_parts.join(" | "))

      dm_msg = persist_message(
        role: "dm",
        content: dm_response[:narrative],
        message_type: dm_response[:roll_request].present? ? "roll_request" : "narrative",
        metadata: { roll_request: dm_response[:roll_request] }.compact_blank
      )
      result_messages << dm_msg

      if dm_response[:advance_stage]
        advance_msg = advance_story_stage!
        result_messages << advance_msg if advance_msg
      end

    rescue AiError => e
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
  # Call 1: Sanitization
  # ----------------------------------------------------------------

  def sanitize_input(player_input)
    prompt_summary = "Sanitize: \"#{@log.truncate(player_input)}\""

    raw = @ai.chat(
      system_prompt: DungeonMaster::Prompts::SANITIZATION_SYSTEM_PROMPT,
      user_message: player_input,
      max_tokens: 300
    )

    parsed = @ai.parse_json(raw, fallback_as: :sanitization)
    @log.ai_log!("sanitization", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status)

    unless parsed.key?("safe")
      raise AiError, "Sanitization response missing 'safe' field"
    end

    {
      safe: parsed["safe"],
      sanitized_input: parsed["sanitized_input"] || player_input,
      reason: parsed["reason"]
    }
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("sanitization", prompt_summary, e, raw_response: fallback_raw)
    raise
  end

  # ----------------------------------------------------------------
  # Call 2: DM Response
  # ----------------------------------------------------------------

  def generate_dm_response(sanitized_input, call_type: "dm_response")
    prompt_summary = "DM prompt: \"#{@log.truncate(sanitized_input)}\""
    raw = nil

    history = DungeonMaster::History.build(@adventure)
    history << { role: "user", content: sanitized_input }

    raw = @ai.chat(
      system_prompt: DungeonMaster::Prompts.dm_system_prompt(@adventure, @config),
      messages: history,
      max_tokens: 4096
    )

    parsed = @ai.parse_json(raw, fallback_as: :dm_response)
    @log.ai_log!(call_type, prompt_summary, raw, parsed, parse_status: @ai.last_parse_status)

    {
      narrative: parsed["narrative"] || "The Dungeon Master pauses thoughtfully...",
      reasoning: parsed["reasoning"],
      advance_stage: parsed["advance_stage"] == true,
      roll_request: parsed["roll_request"]
    }
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!(call_type, prompt_summary, e, raw_response: fallback_raw)
    raise
  end

  # ----------------------------------------------------------------
  # Stage Advancement
  # ----------------------------------------------------------------

  def advance_story_stage!
    current    = @adventure.story_state
    all_stages = current.story.story_states.kept.order(position: :asc)
    next_stage = all_stages.detect { |s| s.position > current.position }

    return nil unless next_stage

    @adventure.update!(story_state: next_stage)

    persist_message(
      role: "system",
      content: "📖 The story advances: #{next_stage.description}",
      message_type: "stage_advance"
    )
  end

  # ----------------------------------------------------------------
  # Message Persistence
  # ----------------------------------------------------------------

  def persist_message(role:, content:, message_type:, metadata: {})
    @adventure.adventure_messages.create!(
      role: role,
      content: content,
      message_type: message_type,
      metadata: metadata
    )
  end

  # ----------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------

  def log_dm_reasoning(dm_response)
    reasoning = dm_response[:reasoning] || "No reasoning provided"
    log_parts = ["DM responded. Reasoning: #{reasoning}"]
    log_parts << "Advance stage: YES" if dm_response[:advance_stage]
    log_parts << "Roll requested: #{dm_response[:roll_request]['description']}" if dm_response[:roll_request].present?
    @log.dm_log!(log_parts.join(" | "))
  end
end
