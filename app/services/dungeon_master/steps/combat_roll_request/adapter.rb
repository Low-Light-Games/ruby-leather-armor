# frozen_string_literal: true

module DungeonMaster
  module Steps
    module CombatRollRequest
      # Translates the flat CombatRollRequest JSON into the
      # `[intent, evaluations]` tuple the rest of the pipeline already
      # consumes, mirroring `Steps::RollRequest::Adapter`. The single
      # branch that differs: combat-domain rolls (`attack_roll` /
      # `saving_throw`) are passed through
      # `Phases::CombatMechanicResolution.normalize_player_roll` so the
      # DC comes from the sheet + grid, never from the model.
      #
      # When the model emits a non-combat roll (`skill_check`) the
      # branch is identical to the out-of-combat adapter — no
      # CombatMechanicResolution lookup needed.
      class Adapter
        DOMAIN_PRIORITY = %w[combat buff social traversal exploration rest inventory].freeze
        NO_INVOLVEMENT_TEXT = '(no mechanical involvement in this domain)'

        def self.call(parsed:, intention:, adventure:, sheet:, log: nil)
          new(parsed: parsed, intention: intention, adventure: adventure, sheet: sheet, log: log).call
        end

        def initialize(parsed:, intention:, adventure:, sheet:, log:)
          @parsed = (parsed || {}).deep_symbolize_keys
          @intention = intention.to_s
          @adventure = adventure
          @sheet = sheet
          @log = log
        end

        def call
          [build_intent, build_evaluations]
        end

        private

        def build_intent
          {
            intention: @intention,
            expand_scene: false,
            destination: nil,
            affected_contexts: affected_contexts,
            transition: nil,
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
          case raw[:type].to_s
          when 'attack_roll', 'saving_throw' then normalize_combat_roll(raw)
          else                                    normalize_generic_roll(raw)
          end
        end

        def normalize_combat_roll(raw)
          context = combat_resolution_context
          DungeonMaster::Steps::Phases::CombatMechanicResolution
            .send(:normalize_player_roll, raw, 0, context: context)
            .deep_symbolize_keys
            .merge(rule_slug: raw[:rule_slug])
            .compact
        rescue DungeonMaster::CombatMechanicResolutionError => e
          @log&.play_log!(
            'combat_mech_eval_resolution_error',
            "CombatRollRequest: #{e.message}",
            parsed_response: { raw: raw }
          )
          # Fall back to a generic shape so the player still sees something
          # rather than a 500 — surface the error in mechanical_summary so
          # the verdict step can narrate it. Combat math defaults to nil DC.
          {
            type: raw[:type], domain: 'combat',
            description: raw[:description].presence || mechanical_summary,
            rule_slug: raw[:rule_slug], dc: nil,
            error: e.message
          }.compact
        end

        def normalize_generic_roll(raw)
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
            situational_modifiers: Array(raw[:situational_modifiers]).map(&:deep_symbolize_keys)
          }.compact
        end

        def combat_resolution_context
          combat_ctx = @adventure.combat_context.is_a?(Hash) ? @adventure.combat_context : {}
          DungeonMaster::Steps::Phases::CombatMechanicResolution::CombatResolutionContext.new(
            combat_ctx: combat_ctx,
            adventure: @adventure,
            sheet: @sheet,
            lookup_context: DungeonMaster::WorldTurn::ParticipantLookup::LookupContext.new(
              combat_ctx: combat_ctx, player_sheet: @sheet, adventure: @adventure
            )
          )
        end

        def affected_contexts
          domains = Array(@parsed[:affected_domains]).map { |d| d.to_s.downcase }
                                                     .reject(&:blank?).uniq
          # Combat free-text always touches combat, even if the model omits it.
          domains << 'combat' unless domains.include?('combat')
          DOMAIN_PRIORITY.select { |d| domains.include?(d) } + (domains - DOMAIN_PRIORITY)
        end

        def primary_domain
          'combat'
        end

        def consequences
          Array(@parsed[:consequences]).map(&:to_s)
        end

        def mechanical_summary
          @parsed[:mechanical_summary].to_s.presence || '(no mechanical summary)'
        end

        def domain_results
          domains = affected_contexts
          {}.tap do |h|
            domains.each do |domain|
              h[domain] = {
                domain: domain,
                affected: true,
                macro_significant: false,
                expand_scene: false,
                transition: nil,
                destination: nil,
                combatants: []
              }
            end
          end
        end
      end
    end
  end
end
