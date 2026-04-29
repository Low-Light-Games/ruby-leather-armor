# frozen_string_literal: true

module DungeonMaster
  module Steps
    module RollRequest
      # Translates the flat RollRequest JSON into the `[intent, evaluations]`
      # tuple that the rest of the pipeline already consumes from
      # `Steps::ParallelEvaluation`. Keeping the boundary stable means the
      # downstream sanity gate, mechanical path, time keeper, encounter
      # dispatch, and social scene branches need ZERO changes when this
      # step is toggled on.
      #
      # The intent shape mirrors `BeaconPhase#converge_beacons`:
      #   { intention, expand_scene, destination, affected_contexts,
      #     transition, macro_significant, combat_ending, domain_results }
      #
      # The evaluations array mirrors `MechEvalPhase#parse_mech_eval_results`:
      #   [ { domain, player_rolls, npc_actions, consequences,
      #       mechanical_summary } ]
      #
      # When `needs_roll: false`, evaluations is empty unless any domain is
      # affected — an "affected but no roll" outcome (e.g. talking to an NPC
      # with no skill check needed) becomes a single evaluation entry with
      # an empty player_rolls array, so the existing
      # `merge_mechanical_evaluations_and_prepare_rolls` flow recognizes the
      # action as resolvable without rolls.
      class Adapter
        DOMAIN_PRIORITY = %w[combat buff social traversal exploration rest inventory].freeze
        NO_INVOLVEMENT_TEXT = '(no mechanical involvement in this domain)'

        def self.call(parsed:, intention:)
          new(parsed: parsed, intention: intention).call
        end

        def initialize(parsed:, intention:)
          @parsed    = (parsed || {}).deep_symbolize_keys
          @intention = intention.to_s
        end

        def call
          [build_intent, build_evaluations]
        end

        private

        def build_intent
          {
            intention: @intention,
            expand_scene: expand_scene?,
            destination: destination,
            affected_contexts: affected_contexts,
            transition: transition,
            macro_significant: false,
            combat_ending: false,
            domain_results: domain_results
          }
        end

        def build_evaluations
          domains = affected_contexts
          return [] if domains.empty?

          rolls = needs_roll? ? [normalized_roll] : []

          domains.map do |domain|
            {
              domain: domain,
              player_rolls: domain == primary_domain ? rolls : [],
              npc_actions: [],
              consequences: domain == primary_domain ? consequences : [],
              mechanical_summary: domain == primary_domain ? mechanical_summary : NO_INVOLVEMENT_TEXT
            }
          end
        end

        def needs_roll?
          @parsed[:needs_roll] == true && @parsed[:roll].is_a?(Hash)
        end

        def normalized_roll
          raw = @parsed[:roll].deep_symbolize_keys
          {
            type: raw[:type].presence || 'skill_check',
            skill: raw[:skill],
            save: raw[:save],
            dc: raw[:dc],
            description: raw[:description].presence || mechanical_summary,
            domain: primary_domain,
            rule_slug: raw[:rule_slug],
            take_10_eligible: raw[:take_10_eligible] == true,
            take_20_eligible: raw[:take_20_eligible] == true,
            situational_modifiers: DungeonMaster::Rolls::SituationalModifiers.normalize(raw[:situational_modifiers])
          }.compact
        end

        def affected_contexts
          domains = Array(@parsed[:affected_domains]).map { |d| d.to_s.downcase }
                                                     .reject(&:blank?).uniq
          DOMAIN_PRIORITY.select { |d| domains.include?(d) } + (domains - DOMAIN_PRIORITY)
        end

        def primary_domain
          affected_contexts.first
        end

        def expand_scene?
          @parsed[:expand_scene] == true && affected_contexts.include?('social')
        end

        def transition
          t = @parsed[:transition].to_s
          t.presence
        end

        def destination
          @parsed[:destination].presence
        end

        def consequences
          Array(@parsed[:consequences]).map(&:to_s)
        end

        def mechanical_summary
          @parsed[:mechanical_summary].to_s.presence || '(no mechanical summary)'
        end

        def domain_results
          # Mirrors the shape `BeaconPhase#converge_beacons` writes so any
          # downstream code that reads `intent[:domain_results][domain]`
          # still works (used by combat-start dispatch in
          # ParallelEvaluation#prepare_canonical_combatants).
          domains = affected_contexts
          combatants = normalized_combatants
          {}.tap do |h|
            domains.each do |domain|
              h[domain] = {
                domain: domain,
                affected: true,
                macro_significant: false,
                expand_scene: domain == 'social' && expand_scene?,
                transition: domain == 'combat' ? transition : nil,
                destination: domain == 'traversal' ? destination : nil,
                combatants: domain == 'combat' ? combatants : []
              }
            end
          end
        end

        def normalized_combatants
          Array(@parsed[:combatants]).flat_map do |entry|
            case entry
            when Hash
              key, value = entry.to_a.first
              count = value.to_i
              count.positive? ? Array.new(count, key.to_s) : [key.to_s]
            else
              [entry.to_s]
            end
          end.reject(&:blank?)
        end
      end
    end
  end
end
