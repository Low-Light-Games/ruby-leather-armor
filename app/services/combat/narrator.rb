# frozen_string_literal: true

module Combat
  # PR-G of the combat-determinism arc — see docs/combat_redesign.md.
  #
  # Takes the structured End Turn round log (NPC events emitted by
  # Combat::NpcTurn) and produces one paragraph of flavor narration.
  # Distinct from the default `narrate` step both in prompt voice (PF1e
  # combat: short sentences, weapon impact, blood-and-steel) and in
  # input shape — the model is NOT asked to adjudicate anything.
  # Mechanics are already settled; this is pure narrative pass.
  module Narrator
    module_function

    # @param round [Integer]
    # @param npc_events [Array<Hash>] from Combat::NpcTurn
    # @param deps [Hash] adventure:, sheet:, ai:, config:, log: (optional)
    # @return [String, nil]
    def call(round:, npc_events:, **deps)
      return nil if npc_events.empty?

      raw = deps.fetch(:ai).chat(**chat_params(round, npc_events, deps))
      raw.to_s.strip.presence
    rescue StandardError => e
      deps[:log]&.play_log!('combat_narrator_failure',
                            "Combat narrator failed: #{e.message}",
                            parsed_response: { round: round, npc_events: npc_events.length })
      Rails.logger.warn("[Combat::Narrator] failed: #{e.message}")
      nil
    end

    def chat_params(round, npc_events, deps)
      context = Narrator::Context.new(
        round: round, npc_events: npc_events,
        adventure: deps[:adventure], sheet: deps[:sheet]
      )
      Narrator::StepParams.new(context: context, config: deps.fetch(:config)).to_h
    end
  end
end
