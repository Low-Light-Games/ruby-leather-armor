# frozen_string_literal: true

module PlayerTurn
  module Steps
    module CombatRollRequest
      class Context
        attr_reader :intent, :scene_retrieval, :relevant_rules, :attack_options,
                    :action_economy, :threats, :battlefield, :combat_state,
                    :current_location_name

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
              battlefield_summary: Battlefield::PromptSerializer.slice_for_adventure(adventure)
            },
            state: { round: combat_state.round, current_turn: combat_state.current_turn,
                     current_location_name: adventure.current_location&.name }
          )
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

        def attack_options_text
          return '(no legal attack options available right now)' if @attack_options.empty?

          @attack_options.map { |opt| attack_option_line(opt) }.join("\n")
        end

        def threats_text
          return '(no immediate threats)' if @threats.empty?

          @threats.map { |t| "- #{t[:name]} at (#{t[:x]}, #{t[:y]}) — #{t[:distance_squares] * 5}ft" }.join("\n")
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
