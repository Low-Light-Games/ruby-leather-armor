# frozen_string_literal: true

module PlayerTurn
  module Steps
    module CastResolve
      private

      def run_cast_resolve(intention)
        broadcast_progress("The stage manager is finding the cast...")

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
                    "Cast: #{roster.members.map(&:name).join(', ').truncate(180)}"
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
