# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Compound action detection.
    # Analyzes player input for multiple sequential actions and returns
    # an ordered array of action entries. Single actions return a one-element
    # array. Skipped entirely when the action_queue toggle is off.
    module Sequencer
      private

      def run_sequencer(sanitized_input)
        unless @config.get("action_queue")
          return [default_action_entry(sanitized_input)]
        end

        return [default_action_entry(sanitized_input)] if combat_active?

        prompt_summary = "Sequencer: \"#{@log.truncate(sanitized_input)}\""
        system_prompt = PromptRenderer.render("sequencer")
        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        parsed = timed_ai_call("sequencer", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                          step_name: "sequencer", model: @config.model_for("sequencer"))
          [raw, @ai.parse_json(raw)]
        end

        actions = Array(parsed["actions"]).filter_map { |entry| normalize_action_entry(entry) }
        actions = [default_action_entry(sanitized_input)] if actions.empty?

        if actions.size > 1
          @log.log!(:info, "Sequencer detected #{actions.size} sequential actions: #{actions.inspect}")
        end

        actions
      end

      def normalize_action_entry(entry)
        case entry
        when String
          default_action_entry(entry)
        when Hash
          text = (entry["text"] || entry[:text]).to_s.strip
          return nil if text.blank?

          {
            "text" => text,
            "depends_on_index" => normalize_depends_on_index(entry["depends_on_index"] || entry[:depends_on_index]),
            "prerequisite" => normalize_prerequisite(entry["prerequisite"] || entry[:prerequisite]),
            "abort_on_failed_prerequisite" => (entry["abort_on_failed_prerequisite"] || entry[:abort_on_failed_prerequisite]) == true
          }
        end
      end

      def default_action_entry(text)
        {
          "text" => text.to_s.strip,
          "depends_on_index" => nil,
          "prerequisite" => nil,
          "abort_on_failed_prerequisite" => false
        }
      end

      def normalize_depends_on_index(value)
        return nil if value.blank?

        idx = value.to_i
        idx >= 0 ? idx : nil
      end

      def normalize_prerequisite(value)
        text = value.to_s.strip
        text.present? ? text : nil
      end
    end
  end
end
