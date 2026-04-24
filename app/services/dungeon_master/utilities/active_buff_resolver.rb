# frozen_string_literal: true

module DungeonMaster
  module Utilities
    module ActiveBuffResolver
      module_function

      def resolve(source_id:, source_type:, adventure:, sheet:, log: nil, allowed_class_ability_ids: nil, buffs_add_entry: {})
        current_game_hours = Utilities::GameClock.absolute_hours(adventure.time_context)

        case source_type.to_s
        when "spell"
          resolve_spell(source_id, sheet: sheet, current_game_hours: current_game_hours, log: log)
        when "item"
          resolve_item(source_id, current_game_hours: current_game_hours, log: log)
        when "class_ability"
          resolve_class_ability(
            source_id,
            sheet: sheet,
            current_game_hours: current_game_hours,
            buffs_add_entry: buffs_add_entry,
            log: log,
            allowed_class_ability_ids: allowed_class_ability_ids
          )
        else
          PipelineWarn.emit(log, "[ActiveBuffResolver] Unknown source_type '#{source_type}' for '#{source_id}' — skipped")
          []
        end
      end

      def resolve_spell(source_id, sheet:, current_game_hours:, log: nil)
        defn = SpellDefinition.find_by(id: source_id)
        unless defn
          PipelineWarn.emit(log, "[ActiveBuffResolver] SpellDefinition '#{source_id}' not found — skipped")
          return []
        end

        caster_level = sheet.level.to_i
        duration_hours = ActiveBuffResolverNumbers.duration_hours_from_formula(defn.duration_formula, level: caster_level)
        expires_at = duration_hours ? current_game_hours + duration_hours : nil

        ActiveBuffEffectRows.build_buff_rows(
          source_id,
          "spell",
          ActiveBuffEffectRows.filter_effects(CharacterStats::PersistedJsonArray.list(defn.effects)),
          expires_at: expires_at,
          caster_level: caster_level
        )
      end

      def resolve_item(source_id, current_game_hours:, log: nil)
        defn = ItemDefinition.find_by(id: source_id)
        unless defn
          PipelineWarn.emit(log, "[ActiveBuffResolver] ItemDefinition '#{source_id}' not found — skipped")
          return []
        end

        formula = (defn.properties || {})["duration_formula"]
        duration_hours = ActiveBuffResolverNumbers.duration_hours_from_formula(formula, level: nil)
        expires_at = duration_hours ? current_game_hours + duration_hours : nil

        ActiveBuffEffectRows.build_buff_rows(
          source_id,
          "item",
          ActiveBuffEffectRows.filter_effects(CharacterStats::PersistedJsonArray.list(defn.effects)),
          expires_at: expires_at,
          caster_level: nil
        )
      end

      def resolve_class_ability(source_id, sheet:, current_game_hours:, buffs_add_entry:, log: nil, allowed_class_ability_ids: nil)
        entry = buffs_add_entry.deep_stringify_keys if buffs_add_entry.is_a?(Hash)
        entry ||= {}
        defn = ClassAbilityDefinition.find_by(id: source_id)
        unless defn
          PipelineWarn.emit(log, "[ActiveBuffResolver] ClassAbilityDefinition '#{source_id}' not found — skipped")
          return []
        end

        unless sheet.respond_to?(:class_ability_definitions)
          PipelineWarn.emit(log, "[ActiveBuffResolver] class_ability '#{source_id}' sheet has no class abilities — skipped")
          return []
        end

        allowed = if allowed_class_ability_ids
                    allowed_class_ability_ids.include?(source_id.to_s)
                  else
                    sheet.class_ability_definitions.exists?(id: source_id.to_s)
                  end
        unless allowed
          PipelineWarn.emit(log, "[ActiveBuffResolver] class_ability '#{source_id}' not available for this character — skipped")
          return []
        end

        from_definition = ActiveBuffEffectRows.filter_effects(CharacterStats::PersistedJsonArray.list(defn.effects))
        from_mutation = ActiveBuffEffectRows.normalize_adjudicated_effects(entry["adjudicated_effects"], log: log)
        merged = from_definition + from_mutation

        if merged.empty?
          PipelineWarn.emit(log, "[ActiveBuffResolver] class_ability '#{source_id}' has no catalog or adjudicated effects — skipped")
          return []
        end

        duration_hours = if entry["adjudicated_duration_hours"].present?
                           entry["adjudicated_duration_hours"].to_f
                         else
                           ActiveBuffResolverNumbers.duration_hours_from_formula(defn.duration_formula, level: sheet.level.to_i)
                         end
        expires_at = duration_hours ? current_game_hours + duration_hours : nil

        ActiveBuffEffectRows.build_buff_rows(
          source_id,
          "class_ability",
          merged,
          expires_at: expires_at,
          caster_level: sheet.level.to_i
        )
      end
    end
  end
end
