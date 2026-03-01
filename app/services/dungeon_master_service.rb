# frozen_string_literal: true

# Orchestrates the AI Dungeon Master pipeline.
#
# Delegates to:
#   DungeonMaster::Prompts   – system prompt text
#   DungeonMaster::AiClient  – OpenAI transport & JSON parsing
#   DungeonMaster::History   – conversation context builder
#   DungeonMaster::Logging   – DmLog / AiLog persistence
#   DungeonMaster::Rules     – category-specific rule text
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

  def process_player_prompt(player_input)
    player_msg = persist_message(role: "player", content: player_input, message_type: "narrative")
    result_messages = [player_msg]

    begin
      # --- Phase 1: Triage (sanitization + classification) ---
      triage = run_triage(player_input)

      threshold = @config.sanitization_threshold

      if triage[:danger_score] >= threshold
        @log.dm_log!(
          "Message \"#{@log.truncate(player_input)}\" was rejected " \
          "(danger: #{triage[:danger_score]}/100, threshold: #{threshold}). " \
          "Reason: #{triage[:reason]}"
        )
        rejection = persist_message(
          role: "system",
          content: triage[:reason] || "Your input was rejected. Please try a valid in-character action.",
          message_type: "sanitization_fail"
        )
        return { messages: [player_msg, rejection] }
      end

      clean_input = triage[:sanitized_input]
      category = triage[:category]

      classification_reason = triage[:classification_reasoning]

      if clean_input != player_input
        @log.dm_log!(
          "Message \"#{@log.truncate(player_input)}\" had to be sanitized " \
          "(danger: #{triage[:danger_score]}/100). Clean version: \"#{@log.truncate(clean_input)}\" | " \
          "Category: #{category}#{classification_reason ? " (#{classification_reason})" : ''}"
        )
      else
        @log.dm_log!(
          "Message \"#{@log.truncate(player_input)}\" passed sanitization " \
          "(danger: #{triage[:danger_score]}/100, threshold: #{threshold}). " \
          "Category: #{category}#{classification_reason ? " (#{classification_reason})" : ''}"
        )
      end

      # --- Phase 2: DM Response (unified or sequential) ---
      dm_response = run_dm_response(clean_input, category: category)

      log_dm_reasoning(dm_response)
      persist_contexts(dm_response, category: category)

      dm_msg = persist_message(
        role: "dm",
        content: dm_response[:narrative],
        message_type: dm_response[:roll_request].present? ? "roll_request" : "narrative",
        metadata: { roll_request: dm_response[:roll_request] }.compact_blank
      )
      result_messages << dm_msg

      if dm_response[:adventure_complete]
        complete_msg = persist_message(
          role: "system",
          content: "The adventure has reached its conclusion.",
          message_type: "adventure_complete"
        )
        result_messages << complete_msg
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

  def process_roll_result(roll_value, roll_description)
    roll_msg = persist_message(
      role: "player",
      content: "🎲 Rolled #{roll_value} for: #{roll_description}",
      message_type: "roll_result",
      metadata: { roll_value: roll_value, roll_description: roll_description }
    )

    result_messages = [roll_msg]

    begin
      # Rolls are continuations — skip classification, infer from current context
      dm_response = run_dm_response(
        "The player rolled a #{roll_value} for #{roll_description}.",
        category: nil,
        call_type: "roll_response"
      )

      reasoning = dm_response[:reasoning] || "No reasoning provided"
      log_parts = ["Roll result #{roll_value} for \"#{roll_description}\". DM reasoning: #{reasoning}"]
      log_parts << "Adventure complete: YES" if dm_response[:adventure_complete]
      @log.dm_log!(log_parts.join(" | "))

      persist_contexts(dm_response, category: nil)

      dm_msg = persist_message(
        role: "dm",
        content: dm_response[:narrative],
        message_type: dm_response[:roll_request].present? ? "roll_request" : "narrative",
        metadata: { roll_request: dm_response[:roll_request] }.compact_blank
      )
      result_messages << dm_msg

      if dm_response[:adventure_complete]
        complete_msg = persist_message(
          role: "system",
          content: "The adventure has reached its conclusion.",
          message_type: "adventure_complete"
        )
        result_messages << complete_msg
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
  # Phase 1: Triage (sanitization + classification)
  # ----------------------------------------------------------------

  def run_triage(player_input)
    if @config.classification_merged?
      triage_merged(player_input)
    else
      triage_parallel(player_input)
    end
  end

  def triage_merged(player_input)
    prompt_summary = "Triage (merged): \"#{@log.truncate(player_input)}\""
    system_prompt = DungeonMaster::Prompts::TRIAGE_SYSTEM_PROMPT
    request_body = { system_prompt: system_prompt, user_message: player_input }

    raw = @ai.chat(
      system_prompt: system_prompt,
      user_message: player_input,
      max_tokens: 400
    )

    parsed = @ai.parse_json(raw, fallback_as: :sanitization)
    @log.ai_log!("triage_merged", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)

    unless parsed.key?("danger_score")
      raise AiError, "Triage response missing 'danger_score' field"
    end

    {
      danger_score: parsed["danger_score"].to_i,
      sanitized_input: parsed["sanitized_input"] || player_input,
      reason: parsed["reason"],
      category: normalize_category(parsed["category"]),
      classification_reasoning: parsed["classification_reasoning"]
    }
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("triage_merged", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    raise
  end

  def triage_parallel(player_input)
    sanitize_thread = Thread.new { sanitize_input(player_input) }
    classify_thread = Thread.new { classify_input(player_input) }

    sanitized = sanitize_thread.value
    classification = classify_thread.value

    sanitized.merge(category: classification[:category], classification_reasoning: classification[:classification_reasoning])
  end

  def sanitize_input(player_input)
    prompt_summary = "Sanitize: \"#{@log.truncate(player_input)}\""
    system_prompt = DungeonMaster::Prompts::SANITIZATION_SYSTEM_PROMPT
    request_body = { system_prompt: system_prompt, user_message: player_input }

    raw = @ai.chat(
      system_prompt: system_prompt,
      user_message: player_input,
      max_tokens: 300
    )

    parsed = @ai.parse_json(raw, fallback_as: :sanitization)
    @log.ai_log!("sanitization", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)

    unless parsed.key?("danger_score")
      raise AiError, "Sanitization response missing 'danger_score' field"
    end

    {
      danger_score: parsed["danger_score"].to_i,
      sanitized_input: parsed["sanitized_input"] || player_input,
      reason: parsed["reason"]
    }
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("sanitization", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    raise
  end

  def classify_input(player_input)
    prompt_summary = "Classify: \"#{@log.truncate(player_input)}\""
    system_prompt = DungeonMaster::Prompts::CLASSIFICATION_SYSTEM_PROMPT
    request_body = { system_prompt: system_prompt, user_message: player_input }

    raw = @ai.chat(
      system_prompt: system_prompt,
      user_message: player_input,
      max_tokens: 200
    )

    parsed = @ai.parse_json(raw)
    @log.ai_log!("classification", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)

    {
      category: normalize_category(parsed["category"]),
      classification_reasoning: parsed["classification_reasoning"]
    }
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("classification", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    { category: "dm_query", classification_reasoning: nil }
  end

  # ----------------------------------------------------------------
  # Phase 2: DM Response (unified or sequential)
  # ----------------------------------------------------------------

  def run_dm_response(sanitized_input, category: nil, call_type: "dm_response")
    if @config.response_sequential? && category != "dm_query"
      dm_response_sequential(sanitized_input, category: category)
    else
      dm_response_unified(sanitized_input, category: category, call_type: call_type)
    end
  end

  def dm_response_unified(sanitized_input, category: nil, call_type: "dm_response")
    prompt_summary = "DM (unified) [#{category || 'none'}]: \"#{@log.truncate(sanitized_input)}\""
    raw = nil

    system_prompt = DungeonMaster::Prompts.dm_system_prompt(@adventure, @config, category: category)

    if @config.contexts_only?
      request_body = { system_prompt: system_prompt, user_message: sanitized_input }
      raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input, max_tokens: 4096)
    else
      history = DungeonMaster::History.build(@adventure)
      history << { role: "user", content: sanitized_input }
      request_body = { system_prompt: system_prompt, messages: history }
      raw = @ai.chat(system_prompt: system_prompt, messages: history, max_tokens: 4096)
    end

    parsed = @ai.parse_json(raw, fallback_as: :dm_response)
    @log.ai_log!(call_type, prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)

    {
      narrative: parsed["narrative"] || "The Dungeon Master pauses thoughtfully...",
      reasoning: parsed["reasoning"],
      adventure_complete: parsed["adventure_complete"] == true,
      roll_request: parsed["roll_request"],
      immediate_context: parsed["immediate_context"],
      story_summary: parsed["story_summary"]
    }
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!(call_type, prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    raise
  end

  def dm_response_sequential(sanitized_input, category: nil)
    scene_thread = Thread.new { update_scene_context(sanitized_input, category: category) }
    needs_thread = Thread.new { resolve_action_needs(sanitized_input, category: category) }

    scene_result = scene_thread.value
    action_needs = needs_thread.value
    updated_immediate = scene_result["immediate_context"] || @adventure.immediate_context

    chronicle_result = update_story_chronicle(sanitized_input, updated_immediate)
    updated_summary = chronicle_result["story_summary"] || @adventure.story_summary

    narrative_result = generate_narrative(sanitized_input, category: category,
                                         immediate_context: updated_immediate,
                                         story_summary: updated_summary,
                                         validation_needs: action_needs)

    {
      narrative: narrative_result["narrative"] || "The Dungeon Master pauses thoughtfully...",
      reasoning: narrative_result["reasoning"],
      adventure_complete: narrative_result["adventure_complete"] == true,
      roll_request: narrative_result["roll_request"],
      immediate_context: updated_immediate,
      story_summary: updated_summary
    }
  end

  def update_scene_context(sanitized_input, category: nil)
    prompt_summary = "Scene tracker [#{category || 'none'}]: \"#{@log.truncate(sanitized_input)}\""
    raw = nil

    system_prompt = DungeonMaster::Prompts.scene_tracker_prompt(@adventure, category: category)

    request_body = { system_prompt: system_prompt, user_message: sanitized_input }

    raw = @ai.chat(
      system_prompt: system_prompt,
      user_message: sanitized_input,
      max_tokens: 1024
    )

    parsed = @ai.parse_json(raw)
    @log.ai_log!("scene_tracker", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)
    parsed
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("scene_tracker", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    @log.dm_log!("Scene tracker failed: #{e.message} — keeping current context")
    {}
  end

  def update_story_chronicle(sanitized_input, updated_immediate_context)
    prompt_summary = "Story chronicler: \"#{@log.truncate(sanitized_input)}\""
    raw = nil

    system_prompt = DungeonMaster::Prompts.story_chronicler_prompt(@adventure, updated_immediate_context)
    request_body = { system_prompt: system_prompt, user_message: sanitized_input }

    raw = @ai.chat(
      system_prompt: system_prompt,
      user_message: sanitized_input,
      max_tokens: 1024
    )

    parsed = @ai.parse_json(raw)
    @log.ai_log!("story_chronicler", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)
    parsed
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("story_chronicler", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    @log.dm_log!("Story chronicler failed: #{e.message} — keeping current summary")
    {}
  end

  def resolve_action_needs(sanitized_input, category: nil)
    prompt_summary = "Action needs [#{category || 'none'}]: \"#{@log.truncate(sanitized_input)}\""
    raw = nil

    system_prompt = DungeonMaster::Prompts.action_needs_prompt(@adventure, category: category)
    request_body = { system_prompt: system_prompt, user_message: sanitized_input }

    raw = @ai.chat(
      system_prompt: system_prompt,
      user_message: sanitized_input,
      max_tokens: 200
    )

    parsed = @ai.parse_json(raw)
    @log.ai_log!("action_needs", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)

    needs = Array(parsed["needs"]).map(&:to_s) & DungeonMaster::Prompts::VALIDATION_NEEDS
    needs.presence
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("action_needs", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    @log.dm_log!("Action needs resolution failed: #{e.message} — narrator will use full character block")
    nil
  end

  def generate_narrative(sanitized_input, category: nil, immediate_context: nil, story_summary: nil, validation_needs: nil)
    prompt_summary = "Narrator [#{category || 'none'}]: \"#{@log.truncate(sanitized_input)}\""
    raw = nil

    system_prompt = DungeonMaster::Prompts.narrator_prompt(
      @adventure, @config, category: category,
      immediate_context: immediate_context, story_summary: story_summary,
      validation_needs: validation_needs
    )

    if @config.contexts_only?
      request_body = { system_prompt: system_prompt, user_message: sanitized_input }
      raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input, max_tokens: 4096)
    else
      history = DungeonMaster::History.build(@adventure)
      history << { role: "user", content: sanitized_input }
      request_body = { system_prompt: system_prompt, messages: history }
      raw = @ai.chat(system_prompt: system_prompt, messages: history, max_tokens: 4096)
    end

    parsed = @ai.parse_json(raw, fallback_as: :dm_response)
    @log.ai_log!("narrator", prompt_summary, raw, parsed, parse_status: @ai.last_parse_status, request_body: request_body)
    parsed
  rescue AiError => e
    fallback_raw = raw || @ai.last_failed_raw_response
    @log.ai_log_error!("narrator", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
    raise
  end

  # ----------------------------------------------------------------
  # Context Persistence
  # ----------------------------------------------------------------

  def persist_contexts(dm_response, category: nil)
    return if category == "dm_query"

    updates = {}
    updates[:immediate_context] = dm_response[:immediate_context] if dm_response[:immediate_context].present?
    updates[:story_summary] = dm_response[:story_summary] if dm_response[:story_summary].present?
    updates[:current_category] = category if category.present?

    if updates.any?
      @adventure.update!(updates)
      log_context_updates(updates)
    end
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

  def normalize_category(category)
    category = category.to_s.downcase.strip
    DungeonMaster::Prompts::PROMPT_CATEGORIES.include?(category) ? category : "dm_query"
  end

  def log_dm_reasoning(dm_response)
    reasoning = dm_response[:reasoning] || "No reasoning provided"
    log_parts = ["DM responded. Reasoning: #{reasoning}"]
    log_parts << "Adventure complete: YES" if dm_response[:adventure_complete]
    log_parts << "Roll requested: #{dm_response[:roll_request]['description']}" if dm_response[:roll_request].present?
    @log.dm_log!(log_parts.join(" | "))
  end

  def log_context_updates(updates)
    parts = []
    if updates[:immediate_context]
      parts << "Immediate context updated: \"#{@log.truncate(updates[:immediate_context], length: 120)}\""
    end
    if updates[:story_summary]
      parts << "Story summary updated: \"#{@log.truncate(updates[:story_summary], length: 120)}\""
    end
    @log.dm_log!(parts.join(" | ")) if parts.any?
  end
end
