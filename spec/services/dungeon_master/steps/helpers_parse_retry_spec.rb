# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Steps::Helpers do
  let(:ai) do
    instance_double(
      Ai::Client,
      last_model_used: "gpt-4.1-nano",
      last_failed_raw_response: nil,
      last_usage: nil,
    )
  end
  let(:log) do
    double("Logging").tap do |l|
      allow(l).to receive(:ai_log!)
      allow(l).to receive(:ai_log_error!)
      allow(l).to receive(:play_log!)
    end
  end

  let(:host_class) do
    Class.new do
      include DungeonMaster::Steps::Helpers

      def initialize(ai, log)
        @ai = ai
        @log = log
      end

      public :timed_ai_call
    end
  end
  let(:host) { host_class.new(ai, log) }

  describe "#timed_ai_call parse-error retry" do
    it "retries once when last_parse_status is parse_error and the second call succeeds" do
      attempt = 0
      allow(ai).to receive(:last_parse_status) do
        attempt < 2 ? "parse_error" : "success"
      end

      result = host.timed_ai_call("combat_context_update", "summary", { foo: 1 }) do
        attempt += 1
        if attempt == 1
          raise Ai::Error, "Failed to parse AI response as JSON"
        else
          ["{\"unchanged\":true}", { "unchanged" => true }]
        end
      end

      expect(result).to eq("unchanged" => true)
      expect(attempt).to eq(2)
      expect(log).to have_received(:play_log!).with(
        "parse_retry",
        a_string_including("combat_context_update"),
        hash_including(parsed_response: hash_including(step: "combat_context_update")),
      )
      expect(log).to have_received(:ai_log!).once
      expect(log).not_to have_received(:ai_log_error!)
    end

    it "stops after one retry and logs ai_log_error if the second call also parse-errors" do
      allow(ai).to receive(:last_parse_status).and_return("parse_error")

      expect do
        host.timed_ai_call("combat_context_update", "summary", { foo: 1 }) do
          raise Ai::Error, "Failed to parse AI response as JSON"
        end
      end.to raise_error(Ai::Error, /Failed to parse/)

      expect(log).to have_received(:play_log!).with("parse_retry", anything, anything).once
      expect(log).to have_received(:ai_log_error!).once
    end

    it "does not retry on TokenBudgetExceededError even if parse_status is parse_error" do
      allow(ai).to receive(:last_parse_status).and_return("parse_error")

      expect do
        host.timed_ai_call("narrate", "summary", { foo: 1 }) do
          raise Ai::TokenBudgetExceededError.new(step_name: "narrate", budget: nil)
        end
      end.to raise_error(Ai::TokenBudgetExceededError)

      expect(log).not_to have_received(:play_log!)
      expect(log).to have_received(:ai_log_error!)
        .with("narrate", "summary", instance_of(Ai::TokenBudgetExceededError),
              hash_including(status: "token_budget_exceeded"))
    end

    it "does not retry on a non-parse AiError (e.g. api_error)" do
      allow(ai).to receive(:last_parse_status).and_return(nil)

      expect do
        host.timed_ai_call("mechanic", "summary", { foo: 1 }) do
          raise Ai::Error, "Rate limited by OpenAI"
        end
      end.to raise_error(Ai::Error, /Rate limited/)

      expect(log).not_to have_received(:play_log!)
      expect(log).to have_received(:ai_log_error!).once
    end
  end
end
