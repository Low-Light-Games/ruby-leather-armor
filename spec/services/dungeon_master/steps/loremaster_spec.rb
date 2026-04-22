# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::Steps::Loremaster do
  describe ".turn_evaluator_prompt" do
    let(:inputs) do
      described_class::LoremasterInputs.new(
        what_happened: "The bridge over the Chasm of Teeth collapsed into the gorge.",
        mutations: { "player" => { "conditions_add" => ["off_balance"] } },
        contexts_text: "traversal: {...}\ncombat: {...}",
        active_facts: [
          { fact_id: 42, kind: "entity", text: "The bridge spans the Chasm of Teeth." },
        ],
      )
    end
    let(:config) do
      instance_double(
        DmConfig,
        model_for: "gpt-4o-mini",
        token_budget_for: 600,
      )
    end

    it "returns an evaluator-compatible payload with meta.step=loremaster" do
      payload = described_class.turn_evaluator_prompt(inputs: inputs, config: config)

      expect(payload).to include(
        system_prompt: be_a(String),
        user_message:  be_a(String),
        model:         "gpt-4o-mini",
        max_tokens:    600,
        meta:          { step: "loremaster" },
      )
    end

    it "calls DmConfig#model_for and #token_budget_for with the loremaster key" do
      described_class.turn_evaluator_prompt(inputs: inputs, config: config)

      expect(config).to have_received(:model_for).with("loremaster")
      expect(config).to have_received(:token_budget_for).with("loremaster")
    end

    it "embeds what_happened, mutations, and the active facts into the system prompt" do
      payload = described_class.turn_evaluator_prompt(inputs: inputs, config: config)

      expect(payload[:system_prompt]).to include("bridge over the Chasm of Teeth collapsed")
      expect(payload[:system_prompt]).to include("off_balance")
      expect(payload[:system_prompt]).to include("[42]")
      expect(payload[:system_prompt]).to include("The bridge spans the Chasm of Teeth.")
    end

    it "embeds the JSON schema file so OpenAI Structured Outputs has a shape to enforce" do
      payload = described_class.turn_evaluator_prompt(inputs: inputs, config: config)

      expect(payload[:system_prompt]).to include("replacement_source_idx")
      expect(payload[:system_prompt]).to include('"event"')
      expect(payload[:system_prompt]).to include('"state"')
      expect(payload[:system_prompt]).to include('"entity"')
    end

    it "renders '(none yet)' when the active-facts window is empty" do
      empty_inputs = described_class::LoremasterInputs.new(
        what_happened: "Nothing of note.",
        mutations: {},
        contexts_text: "",
        active_facts: [],
      )
      payload = described_class.turn_evaluator_prompt(inputs: empty_inputs, config: config)

      expect(payload[:system_prompt]).to include("(none yet)")
    end

    it "passes what_happened as the user_message (matches ContextUpdate fan-out pattern)" do
      payload = described_class.turn_evaluator_prompt(inputs: inputs, config: config)

      expect(payload[:user_message]).to eq(inputs.what_happened)
    end

    describe "LoremasterInputs value object" do
      it "is frozen at construction (write-too-early guard, plan claim #6)" do
        expect(inputs).to be_frozen
      end
    end
  end

  describe ".render_seed_prompt" do
    let(:rendered) do
      described_class.render_seed_prompt(
        premise: "A castaway washes ashore after a shipwreck.",
        enriched_world: "The Endless Sea. Salt-crusted. No land visible for a thousand miles.",
        opening_narrative: "You wake to the smell of brine and the cry of gulls. Above you, a splintered mast.",
        initial_contexts_text: "traversal: in_open_water=true\nrest: exhausted=true",
        npcs_text: "(none yet)",
        clues_text: "(none yet)",
        locations_text: "Lost Shore (coast, unknown distance)",
      )
    end

    it "renders the seed call shape header" do
      expect(rendered).to include("seed call")
      expect(rendered).not_to include("turn call")
    end

    it "embeds the premise, enriched world, and opening narrative" do
      expect(rendered).to include("castaway washes ashore")
      expect(rendered).to include("Endless Sea")
      expect(rendered).to include("splintered mast")
    end

    it "embeds the initial contexts and known locations" do
      expect(rendered).to include("in_open_water=true")
      expect(rendered).to include("Lost Shore (coast, unknown distance)")
    end

    it "embeds the JSON schema so Structured Outputs has a shape to enforce" do
      expect(rendered).to include('"event"')
      expect(rendered).to include('"state"')
      expect(rendered).to include("replacement_source_idx")
    end
  end

  describe ".parse_output" do
    it "extracts facts, invalidates, and reasoning from a well-formed response" do
      response = {
        "facts" => [
          { "text" => "party in ocean", "kind" => "state", "entities" => ["party"], "polarity" => "asserts" },
          { "text" => "mast drifted away", "kind" => "event", "entities" => [], "polarity" => "asserts" },
        ],
        "invalidates" => [
          { "fact_id" => 7, "reason" => "mast is gone", "replacement_source_idx" => nil },
        ],
        "reasoning" => "Shipwreck observed.",
      }

      facts, invalidates, reasoning = described_class.parse_output(response)

      expect(facts.length).to eq(2)
      expect(invalidates.length).to eq(1)
      expect(invalidates.first["fact_id"]).to eq(7)
      expect(reasoning).to eq("Shipwreck observed.")
    end

    it "defensively returns empties on a nil parsed body" do
      expect(described_class.parse_output(nil)).to eq([[], [], nil])
    end

    it "defensively returns empties on a non-Hash parsed body (e.g. a JSON array leaked through)" do
      expect(described_class.parse_output([1, 2, 3])).to eq([[], [], nil])
    end

    it "drops non-Hash entries from facts/invalidates arrays without raising" do
      response = {
        "facts" => [
          { "text" => "ok" },
          "a stray string the model emitted",
          nil,
        ],
        "invalidates" => [
          { "fact_id" => 1 },
          42,
        ],
        "reasoning" => nil,
      }

      facts, invalidates, reasoning = described_class.parse_output(response)

      expect(facts.length).to eq(1)
      expect(invalidates.length).to eq(1)
      expect(reasoning).to be_nil
    end
  end
end
