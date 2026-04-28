# frozen_string_literal: true

module DungeonMaster
  module Steps
    module CombatRollRequest
      # Value object for the CombatRollRequest prompt template (PR-E).
      # Carries the combat-aware context that the out-of-combat
      # RollRequest deliberately omits: legal attack options, action
      # economy, threats / flanking facts, and the battlefield slice.
      # The character sheet itself is still NOT in here — combat math
      # (attack bonus, AC, save DC) resolves post-call by code from
      # `attack_option_id` + grid positions, mirroring the legacy
      # combat_mechanic chain.
      #
      # Constructor groups related fields into sub-hashes to keep the
      # signature under the parameter-list cap.
      class Context
        attr_reader :intent, :recent_beats, :relevant_rules, :attack_options,
                    :action_economy, :threats, :battlefield, :combat_state

        # @param retrieval [Hash] recent_beats, relevant_rules
        # @param combat [Hash] attack_options, action_economy, threats, battlefield_summary
        # @param state [Hash] round, current_turn
        def initialize(intent:, retrieval:, combat:, state:)
          @intent = intent
          @recent_beats = Array(retrieval[:recent_beats])
          @relevant_rules = Array(retrieval[:relevant_rules])
          @attack_options = Array(combat[:attack_options])
          @action_economy = combat[:action_economy] || {}
          @threats = Array(combat[:threats])
          @battlefield = combat[:battlefield_summary]
          @combat_state = state || {}
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
