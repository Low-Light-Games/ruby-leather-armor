# frozen_string_literal: true

module DungeonMaster
  # Shared sanitization logic used by both DungeonMasterService and
  # DungeonMasterLightService. Evaluates player input for prompt injection,
  # meta-gaming, and other dangers.
  module Sanitization
    def run_sanitization(player_input)
      if @config.classification_merged?
        sanitize_merged(player_input)
      else
        sanitize_standalone(player_input)
      end
    end

    private

    def sanitize_merged(player_input)
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
        raise DungeonMasterService::AiError, "Triage response missing 'danger_score' field"
      end

      {
        danger_score: parsed["danger_score"].to_i,
        sanitized_input: parsed["sanitized_input"] || player_input,
        reason: parsed["reason"],
        category: parsed["category"]
      }
    rescue DungeonMasterService::AiError => e
      fallback_raw = raw || @ai.last_failed_raw_response
      @log.ai_log_error!("triage_merged", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
      raise
    end

    def sanitize_standalone(player_input)
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
        raise DungeonMasterService::AiError, "Sanitization response missing 'danger_score' field"
      end

      {
        danger_score: parsed["danger_score"].to_i,
        sanitized_input: parsed["sanitized_input"] || player_input,
        reason: parsed["reason"]
      }
    rescue DungeonMasterService::AiError => e
      fallback_raw = raw || @ai.last_failed_raw_response
      @log.ai_log_error!("sanitization", prompt_summary, e, raw_response: fallback_raw, request_body: request_body)
      raise
    end

    def check_sanitization!(player_input, triage)
      threshold = @config.sanitization_threshold

      if triage[:danger_score] >= threshold
        @log.dm_log!(
          "Message \"#{@log.truncate(player_input)}\" was rejected " \
          "(danger: #{triage[:danger_score]}/100, threshold: #{threshold}). " \
          "Reason: #{triage[:reason]}"
        )
        return triage[:reason] || "Your input was rejected. Please try a valid in-character action."
      end

      if triage[:sanitized_input] != player_input
        @log.dm_log!(
          "Message \"#{@log.truncate(player_input)}\" had to be sanitized " \
          "(danger: #{triage[:danger_score]}/100). Clean version: \"#{@log.truncate(triage[:sanitized_input])}\""
        )
      else
        @log.dm_log!(
          "Message \"#{@log.truncate(player_input)}\" passed sanitization " \
          "(danger: #{triage[:danger_score]}/100, threshold: #{threshold})."
        )
      end

      nil
    end
  end
end
