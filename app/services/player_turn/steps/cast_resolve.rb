# frozen_string_literal: true

module PlayerTurn
  module Steps
    # Pipeline step: between Sequencer and RollRequest, identify every
    # creature implicated by the player's intent and resolve each to a
    # real `AdventureNpc` (with `creature_sheet_id`) via the four-tier
    # deterministic lookup in `Encounters::CastResolver`.
    #
    # Returns a `PlayerTurn::CastRoster`. Errors propagate by design:
    # without a roster, RollRequest cannot reference creatures by id and
    # any downstream identity recovery would have to invent again. Per
    # `.cursor/rules/error-reporting-sentry.mdc` the underlying service
    # already reports to Sentry before re-raising; this layer just lets
    # the failure surface so the turn aborts loudly.
    module CastResolve
      private

      def run_cast_resolve(intention)
        broadcast_progress("Reading the scene...")

        members = Encounters::CastResolver.call(
          adventure:   @adventure,
          intent_text: intention,
          ai:          @ai,
          log:         @log,
          config:      @config,
        )
        roster = PlayerTurn::CastRoster.from_adventure_npcs(members)
        log_cast_roster_to_loop(roster, intention)
        roster
      end

      def log_cast_roster_to_loop(roster, intention)
        return unless @loop

        summary = if roster.empty?
                    "No cast in scope"
                  else
                    "Cast: #{roster.entries.map(&:name).join(', ').truncate(180)}"
                  end

        @loop.batch_update!(
          new_data: { "cast_roster" => roster.to_h.deep_stringify_keys },
          timeline_entry: {
            "step"    => "cast_resolve",
            "summary" => summary,
            "at"      => Time.current.iso8601,
          },
        )
      end
    end
  end
end
