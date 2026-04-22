# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Loremaster.
    #
    # Extracts durable narrative facts (events, state, entities) from the
    # factual outcome of a turn — and from the adventure's initial conditions
    # at creation time — and emits them as structured JSON for
    # `DungeonMaster::Lore::ApplyResults` to persist into
    # `adventure_narrative_facts`. The facts store replaces micro-contexts as
    # the dynamic-state input to the World Consistency Check (plan:
    # narrative facts store for world sanity).
    #
    # Two call shapes share one template and one schema:
    #
    # * **Seed call** (`call_shape: "seed"`) — run once at adventure creation
    #   from `Lore::SeedFromAdventure`. The model reads the story premise,
    #   enriched world, opening narrative, initial micro-contexts, NPCs,
    #   clues, and locations, and populates the store with `source: "seed"`
    #   facts so turn 1's world check is not a cold start.
    # * **Turn call** (`call_shape: "turn"`) — run every terminal narrative
    #   phase from `Stagehand` as a third prompt in the Node fan-out
    #   alongside Narrate and ContextUpdate. The model reads `what_happened`,
    #   the mutations hash, the post-mutation micro-context snapshot, and
    #   the active-facts window, and emits new facts + invalidations.
    #
    # This class is inert for C4 — it produces evaluator-compatible prompt
    # payloads and exposes a direct `run(...)` for seeding, but nothing
    # calls it yet. Stagehand wiring (turn call) lands in C6;
    # `Lore::SeedFromAdventure` wiring (seed call) lands in C8. The
    # `Lore::ApplyResults` service that persists the output lands in C5.
    module Loremaster
      STEP_NAME = "loremaster"
      TEMPLATE_NAME = "loremaster"
      SCHEMA_NAME = "loremaster"

      # Value object passed into Stagehand's fan-out payload builder. Frozen
      # at construction so a future pipeline reorder that adds a mutation-
      # producing step after the fan-out starts cannot silently feed
      # Loremaster stale inputs — tests will catch the divergence because
      # Loremaster will be operating on pre-reorder state while the new
      # step writes post-reorder state. This is the "write-too-early
      # guard" invariant (correctness claim #6 in the plan).
      LoremasterInputs = Struct.new(
        :what_happened,
        :mutations,
        :contexts_text,
        :active_facts,
        keyword_init: true,
      ) do
        def initialize(*args, **kwargs)
          super
          freeze
        end
      end

      module_function

      # Builds a Node-evaluator fan_out prompt payload for the turn call.
      # Returns the same shape as `narrate_evaluator_prompt` /
      # `domain_context_evaluator_prompt` in the existing pipeline so
      # `Stagehand#run_parallel_narrative` can append it to its prompts
      # array without any bespoke plumbing.
      def turn_evaluator_prompt(inputs:, config:)
        {
          system_prompt: render_turn_prompt(inputs: inputs),
          # The fan_out transport requires a user_message; we pass
          # what_happened so the model sees the outcome summary in both
          # the system prompt (structured) and the user message
          # (free-text), matching how ContextUpdate's domain prompts work.
          user_message:  inputs.what_happened.to_s,
          model:         config.model_for(STEP_NAME),
          max_tokens:    config.token_budget_for(STEP_NAME),
          meta:          { step: STEP_NAME },
        }
      end

      # Renders the seed-call system prompt. Used by
      # `Lore::SeedFromAdventure` (C8) to issue one direct `AiClient#chat`
      # at adventure creation.
      def render_seed_prompt(premise:, enriched_world:, opening_narrative:,
                             initial_contexts_text:, npcs_text:, clues_text:,
                             locations_text:)
        PromptRenderer.render(
          TEMPLATE_NAME,
          call_shape: "seed",
          premise: premise,
          enriched_world: enriched_world,
          opening_narrative: opening_narrative,
          initial_contexts_text: initial_contexts_text,
          npcs_text: npcs_text,
          clues_text: clues_text,
          locations_text: locations_text,
          schema_json: PromptRenderer.load_schema(SCHEMA_NAME),
        )
      end

      def render_turn_prompt(inputs:)
        PromptRenderer.render(
          TEMPLATE_NAME,
          call_shape: "turn",
          what_happened: inputs.what_happened,
          mutations_json: inputs.mutations.present? ? inputs.mutations.to_json : "(no mutations)",
          contexts_text: inputs.contexts_text,
          active_facts: inputs.active_facts,
          schema_json: PromptRenderer.load_schema(SCHEMA_NAME),
        )
      end

      # Pure parser for a Loremaster response body. Returns a tuple of
      # [facts_array, invalidates_array, reasoning] with defensive
      # defaults so a partially-shaped response does not raise inside
      # the terminal narrative phase. `Lore::ApplyResults` is responsible
      # for reporting malformed responses to Sentry (per the lossy-with-
      # Sentry contract) — this parser's job is to keep downstream code
      # free of `NoMethodError`s on a nil/non-Hash payload.
      def parse_output(parsed)
        return [[], [], nil] unless parsed.is_a?(Hash)

        facts = Array(parsed["facts"]).select { |f| f.is_a?(Hash) }
        invalidates = Array(parsed["invalidates"]).select { |i| i.is_a?(Hash) }
        reasoning = parsed["reasoning"].is_a?(String) ? parsed["reasoning"] : nil

        [facts, invalidates, reasoning]
      end
    end
  end
end
