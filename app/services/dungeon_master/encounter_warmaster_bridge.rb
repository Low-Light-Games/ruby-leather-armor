# frozen_string_literal: true

module DungeonMaster
  # Path A after TimeKeeper: Harbinger left encounter ids on the AdventureLoop; optionally
  # run Warmaster, update the loop, and produce the resolver return payload. Does not write
  # +pipeline_outcome+ — AdventureLoopResolution calls +store_pipeline_outcome!+ with +pipeline_outcome+.
  class EncounterWarmasterBridge
    # Return value from EncounterWarmasterBridge.call: resolver payload (status, intent, etc.)
    # and the string stored as the loop +pipeline_outcome+ narration seed.
    class Result
      attr_reader :payload, :pipeline_outcome

      def initialize(payload:, pipeline_outcome:)
        @payload          = payload
        @pipeline_outcome = pipeline_outcome
      end
    end

    def self.call(loop:, adventure:, sheet:, log:, config:, ai:, intent:, time_result:, mutations:)
      entry_id = loop&.get("encounter_entry_id")
      encounter_entry = EncounterTableEntry.find_by(id: entry_id) if entry_id

      if encounter_entry
        creatures_data = loop&.get("encounter_creatures")
        warmaster_result = Utilities::Warmaster.initialize_from_encounter!(
          adventure: adventure, encounter_entry: encounter_entry,
          creatures_data: creatures_data,
          sheet: sheet, log: log, config: config, ai: ai)

        if warmaster_result[:status] == :awaiting_initiative
          loop&.batch_update!(
            new_tags: { "combat_started" => true },
            new_data: { "creature_count" => warmaster_result[:creature_data]&.size },
            timeline_entry: { "step" => "warmaster", "summary" => "Combat: #{warmaster_result[:creature_data]&.size} creature(s)", "at" => Time.current.iso8601 })

          combined = encounter_verdict_combined(loop)
          return Result.new(
            payload: {
              status: :awaiting_initiative, intent: intent,
              creature_data: warmaster_result[:creature_data],
              mutations: mutations, time_result: time_result
            },
            pipeline_outcome: combined
          )
        end
      end

      combined = encounter_verdict_combined(loop)
      Result.new(
        payload: {
          status: :encounter, intent: intent,
          mutations: mutations, time_result: time_result
        },
        pipeline_outcome: combined
      )
    end

    def self.encounter_verdict_combined(loop)
      encounter_scene = loop&.get("encounter_scene")
      [encounter_scene, loop&.get("verdict_outcome")].compact.join("\n\n").presence
    end
    private_class_method :encounter_verdict_combined
  end
end
