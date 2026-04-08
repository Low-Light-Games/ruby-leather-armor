# frozen_string_literal: true

module DungeonMaster
  module Narrative
    # Assembles merged intent, mutations, PipelineContext, and Stagehand +extra flags from
    # resolver result rows and AdventureLoop +pipeline_outcome+ rows for one accumulated
    # narration pass (multi-action queue, encounter tail, etc.).
    class AccumulatedAssembly
      Result = Struct.new(:merged_intent, :pipeline_context, :mutations, :extra, keyword_init: true)

      def self.call(pipeline:, results:)
        merged_intent = merge_result_intents(results)
        all_loops = AdventureLoop.for_pipeline(pipeline.log.pipeline_run_id).order(:sequence_index)
        all_outcomes = all_loops.filter_map { |l| l.get("pipeline_outcome") }
        all_mutations = results.filter_map { |r| r[:mutations] }
        encounter_triggered = results.any? { |r| r[:status] == :encounter }
        social_scene_triggered = results.any? { |r| r[:status] == :social_scene }

        combined_seed = all_outcomes.join("\n\nThen: ").presence
        combined_mutations = all_mutations.compact.reduce({}) do |acc, m|
          Utilities::HashMerge.deep_merge_presence(acc, m)
        end

        plot_result = pipeline.send(:resolve_plot, merged_intent, verdict_outcome: combined_seed,
          encounter_triggered: encounter_triggered)

        ctx = PipelineContext.new(
          combined_seed: combined_seed,
          dm_brief: plot_result&.dig(:dm_brief),
          player_action: all_loops.filter_map(&:player_intent).join("\nThen: ").presence
        )

        extra = {}
        extra[:encounter_triggered] = true if encounter_triggered
        extra[:social_scene_triggered] = true if social_scene_triggered

        Result.new(
          merged_intent: merged_intent,
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
          affected_contexts: intents.flat_map { |i| Array(i[:affected_contexts]) }.uniq,
          macro_significant: intents.any? { |i| i[:macro_significant] },
          domain_results: intents.last[:domain_results]
        }
      end
      private_class_method :merge_result_intents
    end
  end
end
