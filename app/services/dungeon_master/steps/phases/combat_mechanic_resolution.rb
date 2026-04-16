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
          "fort" => "Fortitude",
          "ref" => "Reflex",
          "will" => "Will"
        }.freeze

        # Code-authoritative fixed DCs keyed by non-numeric ref string from the model.
        FIXED_DC_REF = {}.freeze

        class << self
          # @param parsed [Hash] symbolized parsed_response from evaluator
          def call(parsed:, domain:, adventure:, sheet:, log: nil)
            combat_ctx = adventure.combat_context.is_a?(Hash) ? adventure.combat_context : {}

            rolls = Array(parsed[:player_rolls]).map.with_index do |raw, idx|
              r = raw.deep_symbolize_keys
              normalize_player_roll(r, idx, combat_ctx: combat_ctx, adventure: adventure, sheet: sheet)
            end

            npc_actions = normalize_npc_actions(Array(parsed[:npc_actions]), log: log)
            summary = parsed[:mechanical_summary].to_s

            {
              domain:             domain,
              player_rolls:       rolls,
              npc_actions:        npc_actions,
              consequences:       Array(parsed[:consequences]).map(&:deep_symbolize_keys),
              mechanical_summary: summary
            }
          end

          private

          def normalize_player_roll(raw, idx, combat_ctx:, adventure:, sheet:)
            type = raw[:type].to_s
            base = { domain: "combat" }.merge(raw.except(:dc_formula))

            case type
            when "attack_roll"
              if raw[:dc].present?
                raise DungeonMaster::CombatMechanicResolutionError.new(
                  "attack_roll must not include dc from model (roll index #{idx})",
                  code: :forbidden_attack_dc
                )
              end

              dc = DungeonMaster::WorldTurn::ParticipantLookup.defense_dc_for_target!(
                raw[:target],
                raw[:defense_kind],
                combat_ctx: combat_ctx,
                player_sheet: sheet,
                adventure: adventure
              )
              base.merge(dc: dc)
            when "saving_throw"
              if raw[:dc].present?
                raise DungeonMaster::CombatMechanicResolutionError.new(
                  "saving_throw must not include dc from model (roll index #{idx})",
                  code: :forbidden_save_dc
                )
              end

              dc = resolve_dc_formula(raw[:dc_formula], idx, adventure: adventure, sheet: sheet, combat_ctx: combat_ctx)
              save = raw[:save].to_s.downcase
              skill = SAVE_TO_SKILL_LABEL[save] || save.capitalize
              base.merge(dc: dc, save: save, skill: skill)
            else
              raise DungeonMaster::CombatMechanicResolutionError.new(
                "unsupported player_roll type: #{type.inspect}",
                code: :unsupported_roll_type
              )
            end
          end

          def resolve_dc_formula(formula, idx, adventure:, sheet:, combat_ctx:)
            f = formula.is_a?(Hash) ? formula.deep_symbolize_keys : {}
            kind = f[:kind].to_s
            case kind
            when "fixed"
              resolve_fixed_dc(f, idx)
            when "spell_dc"
              resolve_spell_dc(f, sheet)
            when "ability_dc"
              resolve_ability_dc(f, adventure: adventure, sheet: sheet, combat_ctx: combat_ctx)
            else
              raise DungeonMaster::CombatMechanicResolutionError.new(
                "unsupported dc_formula.kind: #{kind.inspect} (roll index #{idx})",
                code: :unsupported_dc_formula
              )
            end
          end

          def resolve_fixed_dc(f, idx)
            ref = f[:ref].to_s
            dc = FIXED_DC_REF[ref]
            unless dc
              raise DungeonMaster::CombatMechanicResolutionError.new(
                "unknown fixed dc ref: #{ref.inspect} (roll index #{idx})",
                code: :unknown_fixed_ref
              )
            end
            dc.to_i
          end

          def resolve_spell_dc(f, sheet)
            name = f[:spell_name].to_s.strip
            raise DungeonMaster::CombatMechanicResolutionError, "spell_name required" if name.blank?

            spell = SpellDefinition.find_by(name: name) ||
                    SpellDefinition.where("LOWER(name) = ?", name.downcase).first
            unless spell
              raise DungeonMaster::CombatMechanicResolutionError.new(
                "spell not found: #{name.inspect}",
                code: :spell_not_found
              )
            end

            caster = f[:caster].to_s.presence || "player"
            unless caster == "player"
              raise DungeonMaster::CombatMechanicResolutionError,
                    "only player caster supported for spell_dc"
            end

            cls = sheet.character_class.to_s
            ability = DungeonMaster::PathfinderCastingAbility.primary_for_class(cls)
            unless ability
              raise DungeonMaster::CombatMechanicResolutionError,
                    "no primary casting class on sheet for spell_dc"
            end

            levels = spell.class_levels || {}
            slug = cls.downcase.split(%r{[/\s]+}).find { |s| levels.key?(s) }
            unless slug
              raise DungeonMaster::CombatMechanicResolutionError,
                    "spell #{name} not on character class #{cls.inspect}"
            end

            spell_level = levels[slug].to_i
            mod = ability_modifier_from_sheet(sheet, ability)
            10 + spell_level + mod
          end

          def resolve_ability_dc(f, adventure:, sheet:, combat_ctx:)
            pattern = f[:pattern].to_s
            ability = f[:ability].to_s.downcase
            unless %w[strength dexterity constitution intelligence wisdom charisma].include?(ability)
              raise DungeonMaster::CombatMechanicResolutionError, "invalid ability for ability_dc"
            end

            case pattern
            when "half_hd_plus_ability"
              origin = f[:origin_target].to_s.strip
              raise DungeonMaster::CombatMechanicResolutionError, "origin_target required" if origin.blank?

              _k, origin_sheet = DungeonMaster::WorldTurn::ParticipantLookup.resolve_target_sheet!(
                origin,
                combat_ctx: combat_ctx,
                player_sheet: sheet,
                adventure: adventure
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
            ds = sheet.derived_stats || {}
            mods = ds["mods"] || {}
            m = mods[ability.to_s]
            return m.to_i if m

            score = sheet.public_send(ability)
            ((score.to_i - 10) / 2).floor
          end

          def normalize_npc_actions(list, log:)
            allowed = []
            Array(list).each do |a|
              h = a.is_a?(Hash) ? a.deep_symbolize_keys : {}
              next if h.blank?

              if h[:action].to_s != "attack_of_opportunity"
                log&.play_log!("combat_mech_eval_npc_action_dropped",
                  "Dropped npc_action #{h[:action].inspect} (only attack_of_opportunity allowed)")
                next
              end

              allowed << h
            end
            allowed
          end
        end
      end
    end
  end
end
