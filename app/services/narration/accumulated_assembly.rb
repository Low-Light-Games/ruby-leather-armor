# frozen_string_literal: true

module Narration
  class AccumulatedAssembly
    def self.call(pipeline_engine:, results:)
      merged_intent = merge_result_intents(results)
      all_loops = AdventureLoop.for_registry_entry(pipeline_engine.log.registry_entry_uuid).order(:sequence_index)
      all_outcomes = all_loops.filter_map { |l| l.get("pipeline_outcome") }
      all_mutations = results.filter_map { |r| r[:mutations] }
      encounter_triggered = results.any? { |r| r[:status] == :encounter }

      action_outcomes = results.filter_map { |r| r[:action_outcome] }
      mutation_lines  = results.flat_map { |r| Array(r[:mutation_lines]) }
      combined_seed = all_outcomes.join("\n\nThen: ").presence || action_outcomes.join("\n\nThen: ").presence
      combined_mutations = all_mutations.compact.reduce({}) do |acc, m|
        Transformers::HashMerge.deep_merge_presence(acc, m)
      end

      player_death         = results.any? { |r| r[:player_death] }
      player_incapacitated = results.any? { |r| r[:player_incapacitated] }
      death_type = if player_death
                     :player_death
                   elsif player_incapacitated
                     :player_incapacitated
                   end

      ctx = PlayerTurn::Context.new(
        combined_seed: combined_seed,
        player_action: all_loops.filter_map(&:player_intent).join("\nThen: ").presence || merged_intent&.dig(:intention),
        death_type: death_type
      )

      extra = {}
      extra[:encounter_triggered]    = true if encounter_triggered
      extra[:player_death]           = true if player_death
      extra[:player_incapacitated]   = true if player_incapacitated

      all_action_outcomes = action_outcomes + mutation_lines
      extra[:action_outcomes] = all_action_outcomes if all_action_outcomes.any?

      all_world_turn_lines = results.flat_map { |r| Array(r[:world_turn_lines]) }
      extra[:world_turn_lines] = all_world_turn_lines if all_world_turn_lines.any?

      NarrationPhaseInputs.new(
        intent: merged_intent,
        pipeline_context: ctx,
        mutations: combined_mutations.presence,
        extra: extra
      )
    end

    def self.merge_result_intents(results)
      intents = results.map { |r| r[:intent] }.compact
      return intents.first if intents.size <= 1

      {
        intention: intents.map { |i| i[:intention] }.compact.join("; "),
      }
    end
    private_class_method :merge_result_intents
  end
end
