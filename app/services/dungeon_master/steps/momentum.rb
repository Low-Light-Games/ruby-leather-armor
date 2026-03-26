# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Momentum — non-mechanical outcome determination.
    #
    # Runs on the non-mechanical path after TimeKeeper. Determines what
    # factually happened when the player's action required no dice rolls
    # or skill checks. Also identifies which context domains were affected,
    # supplementing the beacons' assessment.
    #
    # Writes `verdict_outcome` and merged `affected_contexts` to @loop.
    module Momentum
      private

      def run_momentum(intent)
        prompt_summary = "Momentum: \"#{@log.truncate(intent[:intention])}\""

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)

        system_prompt = PromptRenderer.render("momentum",
          loop: @loop,
          contexts_text: PromptHelpers.format_contexts(micro_contexts),
          context_domains: PromptHelpers::CONTEXT_FIELDS)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("momentum", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                         max_tokens: @config.token_budget_for("momentum"),
                         step_name: "momentum",
                         model: @config.model_for("momentum"))
          [raw, @ai.parse_json(raw)]
        end

        outcome = parsed["outcome"] || intent[:intention]
        ai_affected = Array(parsed["affected_contexts"]).map(&:to_s) & PromptHelpers::CONTEXT_FIELDS
        beacon_affected = Array(@loop&.get("affected_contexts")).map(&:to_s)
        merged_affected = (beacon_affected | ai_affected).uniq

        loop_data = {
          "verdict_outcome"  => outcome.to_s.truncate(500),
          "pipeline_outcome" => outcome.to_s.truncate(2000),
          "affected_contexts" => merged_affected
        }

        @loop&.batch_update!(
          new_data: loop_data,
          timeline_entry: { "step" => "momentum", "summary" => outcome.to_s.truncate(120), "at" => Time.current.iso8601 })

        apply_mutations(parsed["mutations"]) if parsed["mutations"].present?

        {
          outcome: outcome,
          mutations: parsed["mutations"] || {},
          affected_contexts: merged_affected
        }
      end
    end
  end
end
