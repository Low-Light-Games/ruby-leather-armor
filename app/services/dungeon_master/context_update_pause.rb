# frozen_string_literal: true

module DungeonMaster
  # Micro context update when the pipeline pauses for player rolls: snapshots reflect
  # the in-progress attempt (intent + pending roll list) before mechanics finish.
  #
  # Assumes: `pipeline_engine` includes ContextUpdate (private `run_context_updates`) and exposes `#log`.
  class ContextUpdatePause
    def self.run(pipeline_engine:, intent:, merged:)
      rolls_desc = Array(merged[:player_rolls])
        .map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]}" }.join(", ")
      what_happened = "Player attempting: #{intent[:intention]}. Pending rolls: #{rolls_desc}."
      pipeline_engine.send(:run_context_updates, what_happened, nil, allow_combat_initialization: false)
    rescue StandardError => e
      ApplicationErrorReporter.notify(e, context: { source: "pause_ctx_update" })
      pipeline_engine.log.log!(:warn, "[pause_ctx_update] #{e.class}: #{e.message}")
    end
  end
end
