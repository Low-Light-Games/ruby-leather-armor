# frozen_string_literal: true

module PlayerTurn
  module Steps
    module CombatRollRequest
      class Context
        attr_reader :intent, :scene_retrieval, :relevant_rules, :attack_options,
                    :action_economy, :threats, :battlefield, :combat_state,
                    :current_location_name, :combat_cast_roster

        def self.build(intent:, adventure:, sheet:, ai:, log:,
                       rules_top_k:, beats_top_k:)
          combat_state = Adventures::CombatState.from_adventure(adventure)

          new(
            intent: intent,
            retrieval: {
              scene_retrieval: SceneRetrieval::ForResolution.call(
                adventure: adventure, intent_text: intent, ai: ai, log: log, fact_limit: beats_top_k
              ),
              relevant_rules: Rules::Lookup.call(
                ai: ai, log: log, query_text: "combat: #{intent}", limit: rules_top_k
              )
            },
            combat: {
              attack_options: Combat::Options::AttackOptionBuilder.call(sheet: sheet, adventure: adventure),
              action_economy: combat_state.action_economy,
              threats: build_threats_for_player(adventure: adventure),
              battlefield_summary: Battlefield::PromptSerializer.slice_for_adventure(adventure),
              cast_roster: build_combat_cast_roster(combat_state: combat_state)
            },
            state: { round: combat_state.round, current_turn: combat_state.current_turn,
                     current_location_name: adventure.current_location&.name }
          )
        end

        # @return [Array<Hash>] one `{ id:, name:, attitude: }` per NPC participant with a sheet id
        def self.build_combat_cast_roster(combat_state:)
          combat_state.npc_participants.filter_map do |participant|
            next nil unless participant.actor_sheet_id

            { id: participant.actor_sheet_id, name: participant.name, attitude: participant.attitude }
          end
        end

        def self.build_threats_for_player(adventure:)
          player_pos = ::Combat::Positions.player_position(adventure)
          return [] unless player_pos&.coordinates_present?

          others = ::Combat::Positions.for_adventure(adventure)
                                      .reject { |p| p.token_id == ::Combat::Positions::PLAYER_TOKEN_ID }

          threats = ::Combat::Rules.aoo_threats_against(mover: player_pos, mover_from: player_pos, others: others)
          threats.map { |threat| ThreatSummary.new(threat: threat, player_pos: player_pos).to_h }
        end

        def initialize(intent:, retrieval:, combat:, state:)
          @intent = intent
          @scene_retrieval = retrieval[:scene_retrieval]
          @relevant_rules = Array(retrieval[:relevant_rules])
          @attack_options = Array(combat[:attack_options])
          @action_economy = combat[:action_economy] || {}
          @threats = Array(combat[:threats])
          @battlefield = combat[:battlefield_summary]
          @combat_cast_roster = Array(combat[:cast_roster])
          @combat_state = state || {}
          @current_location_name = @combat_state[:current_location_name]
        end

        def round
          @combat_state[:round]
        end

        def current_turn
          @combat_state[:current_turn]
        end

        def battlefield_summary
          @battlefield
        end

        def action_economy_chips
          chips = []
          chips << 'Standard' if @action_economy['standard_available']
          chips << 'Move'     if @action_economy['move_available']
          chips << 'Swift'    if @action_economy['swift_available']
          chips << 'Free'
          chips
        end

        def attack_options_text
          return '(no legal attack options available right now)' if @attack_options.empty?

          @attack_options.map { |opt| attack_option_line(opt) }.join("\n")
        end

        def threats_text
          return '(no immediate threats)' if @threats.empty?

          @threats.map { |t| "- #{t[:name]} at (#{t[:x]}, #{t[:y]}) — #{t[:distance_squares] * 5}ft" }.join("\n")
        end

        def cast_roster_lines
          return ['(no creatures in scope)'] if @combat_cast_roster.empty?

          @combat_cast_roster.map do |entry|
            "[id=#{entry[:id]}] #{entry[:name]} (#{entry[:attitude]})"
          end
        end

        def cast_roster_empty?
          @combat_cast_roster.empty?
        end

        def cast_roster_ids
          @combat_cast_roster.map { |entry| entry[:id] }
        end

        private

        def attack_option_line(opt)
          damage = opt[:damage_type].to_s.empty? ? opt[:damage] : "#{opt[:damage]} #{opt[:damage_type]}"
          "- #{opt[:id]} | #{opt[:label]} | #{opt[:attack_mode]} vs #{opt[:defense_kind]} | #{damage}"
        end
      end
    end
  end
end
