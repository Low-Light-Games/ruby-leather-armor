# frozen_string_literal: true

module DungeonMaster
  module Steps
    module Phases
      # Normalizes raw combat mech-eval JSON: resolves attack DCs from sheets,
      # computes saving throw DCs from dc_formula, filters npc_actions to AoO only.
      #
      # TODO(concentration): Revisit adding concentration checks when adventure/sheet
      # exposes concentration state (see combat mech-eval plan).
      module CombatMechanicResolution
        SAVE_TO_SKILL_LABEL = {
          'fort' => 'Fortitude',
          'ref' => 'Reflex',
          'will' => 'Will'
        }.freeze

        # Bundles the inputs every CombatMechanicResolution helper
        # needs (combat_context snapshot, adventure, player sheet,
        # WorldTurn::ParticipantLookup context) so the helper signatures
        # don't have to thread four args each.
        class CombatResolutionContext
          attr_reader :combat_ctx, :adventure, :sheet, :lookup_context

          def initialize(combat_ctx:, adventure:, sheet:, lookup_context:)
            @combat_ctx = combat_ctx
            @adventure = adventure
            @sheet = sheet
            @lookup_context = lookup_context
          end
        end

        class << self
          # @param parsed [Hash] symbolized mech-eval response from the evaluator
          #   envelope (caller is responsible for extracting the inner payload)
          def call(parsed:, domain:, adventure:, sheet:, log: nil)
            parsed_mech_eval_response = parsed
            combat_ctx = adventure.combat_context.is_a?(Hash) ? adventure.combat_context : {}
            context = CombatResolutionContext.new(
              combat_ctx: combat_ctx,
              adventure: adventure,
              sheet: sheet,
              lookup_context: DungeonMaster::WorldTurn::ParticipantLookup::LookupContext.new(
                combat_ctx: combat_ctx,
                player_sheet: sheet,
                adventure: adventure
              )
            )

            rolls = normalize_player_rolls(Array(parsed_mech_eval_response[:player_rolls]), context: context)

            npc_actions = normalize_npc_actions(Array(parsed_mech_eval_response[:npc_actions]), log: log)
            summary = parsed_mech_eval_response[:mechanical_summary].to_s

            {
              domain: domain,
              player_rolls: rolls,
              npc_actions: npc_actions,
              consequences: normalize_consequences(parsed_mech_eval_response[:consequences]),
              mechanical_summary: summary
            }
          end

          private

          def normalize_player_rolls(player_roll_entries, context:)
            player_roll_entries.map.with_index do |player_roll_entry, roll_index|
              normalize_player_roll(player_roll_entry.deep_symbolize_keys, roll_index, context: context)
            end
          end

          def normalize_player_roll(raw, idx, context:)
            type = raw[:type].to_s

            case type
            when 'attack_roll'
              if raw[:dc].present?
                raise DungeonMaster::CombatMechanicResolutionError.new(
                  "attack_roll must not include dc from model (roll index #{idx})",
                  code: :forbidden_attack_dc
                )
              end

              option_id = raw[:attack_option_id].to_s
              if option_id.blank?
                raise DungeonMaster::CombatMechanicResolutionError.new(
                  "attack_roll must include attack_option_id (roll index #{idx})",
                  code: :missing_attack_option_id
                )
              end

              option = DungeonMaster::Combat::AttackOptionBuilder.resolve_option_id!(
                sheet: context.sheet,
                adventure: context.adventure,
                option_id: option_id
              )

              dc = DungeonMaster::WorldTurn::ParticipantLookup.defense_dc_for_target!(
                raw[:target],
                option[:defense_kind],
                context: context.lookup_context
              )
              attrs = raw.except(
                :dc_formula, :defense_kind, :attack_option_id,
                :damage, :damage_type, :source_type, :source_id, :attack_mode
              )

              { domain: 'combat' }.merge(attrs).merge(
                attack_mode: option[:attack_mode],
                defense_kind: option[:defense_kind],
                source_type: option[:source_type],
                source_id: option[:source_id],
                damage: option[:damage],
                damage_type: option[:damage_type],
                dc: dc
              ).compact
            when 'saving_throw'
              if raw[:dc].present?
                raise DungeonMaster::CombatMechanicResolutionError.new(
                  "saving_throw must not include dc from model (roll index #{idx})",
                  code: :forbidden_save_dc
                )
              end

              dc = resolve_dc_formula(raw[:dc_formula], idx, context: context)
              save = TextNormalizer.normalized_key(raw[:save])
              skill = SAVE_TO_SKILL_LABEL[save] || save.capitalize
              attrs = raw.except(:dc_formula)
              { domain: 'combat' }.merge(attrs).merge(dc: dc, save: save, skill: skill)
            else
              raise DungeonMaster::CombatMechanicResolutionError.new(
                "unsupported player_roll type: #{type.inspect}",
                code: :unsupported_roll_type
              )
            end
          end

          # The combat_mechanic prompt's example shows `"consequences": []`
          # but does not pin the entry shape — models occasionally emit an
          # array of plain strings ("Aldric closes to melee.") instead of
          # the hash shape downstream code assumes. Coerce defensively so
          # one stylistic drift doesn't crash the whole turn.
          def normalize_consequences(value)
            Array(value).filter_map do |entry|
              case entry
              when Hash   then entry.deep_symbolize_keys
              when String then { description: entry }
              end
            end
          end

          def resolve_dc_formula(formula, idx, context:)
            formula_payload = formula.is_a?(Hash) ? formula.deep_symbolize_keys : {}
            kind = formula_payload[:kind].to_s
            case kind
            when 'spell_dc'
              resolve_spell_dc(formula_payload, context.sheet)
            when 'ability_dc'
              resolve_ability_dc(formula_payload, context: context)
            else
              raise DungeonMaster::CombatMechanicResolutionError.new(
                "unsupported dc_formula.kind: #{kind.inspect} (roll index #{idx})",
                code: :unsupported_dc_formula
              )
            end
          end

          def resolve_spell_dc(formula_payload, sheet)
            name = TextNormalizer.strip(formula_payload[:spell_name])
            raise DungeonMaster::CombatMechanicResolutionError, 'spell_name required' if name.blank?

            spell = SpellDefinition.find_by_name_case_insensitive(name)
            unless spell
              raise DungeonMaster::CombatMechanicResolutionError.new(
                "spell not found: #{name.inspect}",
                code: :spell_not_found
              )
            end

            caster = formula_payload[:caster].to_s.presence || 'player'
            unless caster == 'player'
              raise DungeonMaster::CombatMechanicResolutionError.new(
                'spell_dc only supports player-cast spells (caster must be "player"); use ability_dc for NPC abilities',
                code: :unsupported_npc_spell_dc
              )
            end

            character_class_name = sheet.character_class.to_s
            levels = spell.class_levels || {}
            slug = TextNormalizer.class_slug_tokens(character_class_name).find do |class_token|
              levels.key?(class_token)
            end
            unless slug
              raise DungeonMaster::CombatMechanicResolutionError,
                    "spell #{name} not on character class #{character_class_name.inspect}"
            end

            ability = DungeonMaster::PathfinderCastingAbility.casting_ability_for_slug(slug)
            unless ability
              raise DungeonMaster::CombatMechanicResolutionError.new(
                "no casting ability mapped for class #{slug.inspect} (spell #{name.inspect})",
                code: :no_casting_ability_for_class
              )
            end

            spell_level = levels[slug].to_i
            mod = ability_modifier_from_sheet(sheet, ability)
            10 + spell_level + mod
          end

          def resolve_ability_dc(formula_payload, context:)
            pattern = formula_payload[:pattern].to_s
            ability = TextNormalizer.normalized_key(formula_payload[:ability])
            unless valid_ability_name?(ability)
              raise DungeonMaster::CombatMechanicResolutionError, 'invalid ability for ability_dc'
            end

            case pattern
            when 'half_hd_plus_ability'
              origin = TextNormalizer.strip(formula_payload[:origin_target])
              raise DungeonMaster::CombatMechanicResolutionError, 'origin_target required' if origin.blank?

              origin_sheet = DungeonMaster::WorldTurn::ParticipantLookup.target_sheet!(
                origin,
                context: context.lookup_context
              )
              mod = ability_modifier_from_sheet(origin_sheet, ability)
              hd = origin_sheet.level.to_i
              10 + (hd / 2) + mod
            else
              raise DungeonMaster::CombatMechanicResolutionError,
                    "unsupported ability_dc pattern: #{pattern.inspect}"
            end
          end

          def ability_modifier_from_sheet(sheet, ability)
            name = ability.to_s
            unless CharacterStats::GameRules::ABILITIES.include?(name)
              raise DungeonMaster::CombatMechanicResolutionError,
                    "invalid ability #{ability.inspect} for modifier"
            end
            unless sheet.respond_to?(name)
              raise DungeonMaster::CombatMechanicResolutionError,
                    "sheet does not expose ability #{name.inspect}"
            end

            derived_stats = sheet.derived_stats || {}
            mods = derived_stats['mods'] || {}
            m = mods[name]
            return m.to_i if m

            score = sheet.public_send(name)
            ((score.to_i - 10) / 2).floor
          end

          def valid_ability_name?(ability_name)
            CharacterStats::GameRules::ABILITIES.include?(ability_name)
          end

          def normalize_npc_actions(list, log:)
            allowed = []
            Array(list).each do |a|
              action_payload = a.is_a?(Hash) ? a.deep_symbolize_keys : {}
              next if action_payload.blank?

              if action_payload[:action].to_s != 'attack_of_opportunity'
                log&.play_log!(
                  'combat_mech_eval_npc_action_dropped',
                  "Dropped npc_action #{action_payload[:action].inspect} (only attack_of_opportunity allowed)"
                )
                next
              end

              allowed << action_payload
            end
            allowed
          end
        end
      end
    end
  end
end
