# frozen_string_literal: true

module PlayerTurn
  module Steps
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

      def cast_resolver_evaluator_prompt(intention)
        Encounters::CastResolver.evaluator_prompt(
          adventure:   @adventure,
          intent_text: intention,
          ai:          @ai,
          log:         @log,
          config:      @config,
        )
      end

      def parse_cast_resolver_from_evaluator_result(result, intention)
        members = Encounters::CastResolver.resolve_from_parsed(
          adventure:       @adventure,
          parsed_response: result["parsed_response"] || {},
          intent_text:     intention,
          ai:              @ai,
          log:             @log,
          config:          @config,
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
