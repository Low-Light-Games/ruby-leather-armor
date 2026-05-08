# frozen_string_literal: true

module DungeonMaster
  module Steps
    module CombatRollRequest
      # Value object for the CombatRollRequest prompt template.
      # Carries the combat-aware context that the out-of-combat
      # RollRequest deliberately omits: legal attack options, action
      # economy, threats / flanking facts, and the battlefield slice.
      # The character sheet itself is still NOT in here — combat math
      # (attack bonus, AC, save DC) resolves post-call by code from
      # `attack_option_id` + grid positions via {Phases::CombatMechanicResolution}.
      #
      # Constructor groups related fields into sub-hashes to keep the
      # signature under the parameter-list cap.
      class Context
        attr_reader :intent, :scene_retrieval, :relevant_rules, :attack_options,
                    :action_economy, :threats, :battlefield, :combat_state,
                    :current_location_name

        # Builds the prompt context for an in-combat free-text turn:
        # legal attack options, action economy snapshot, AoO threats,
        # battlefield text, plus RAG-retrieved rules + the player's
        # facts/locations/npcs slice.
        # rubocop:disable Metrics/ParameterLists, Naming/MethodParameterName
        def self.build(intent:, adventure:, sheet:, ai:, log:,
                       rules_top_k:, beats_top_k:)
          combat_ctx = adventure.combat_context.is_a?(Hash) ? adventure.combat_context : {}

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
              action_economy: combat_ctx['action_economy'] || {},
              threats: build_threats_for_player(adventure: adventure),
              battlefield_summary: Battlefield::PromptSerializer.slice_for_adventure(adventure)
            },
            state: { round: combat_ctx['round'], current_turn: combat_ctx['current_turn'],
                     current_location_name: adventure.current_location&.name }
          )
        end
        # rubocop:enable Metrics/ParameterLists, Naming/MethodParameterName

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

        private

        def attack_option_line(opt)
          damage = opt[:damage_type].to_s.empty? ? opt[:damage] : "#{opt[:damage]} #{opt[:damage_type]}"
          "- #{opt[:id]} | #{opt[:label]} | #{opt[:attack_mode]} vs #{opt[:defense_kind]} | #{damage}"
        end
      end
    end
  end
end
