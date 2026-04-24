# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # Resolves a buff source into one or more active_buffs entries ready to be
    # persisted on an AdventureSheet.
    #
    # Each returned entry includes source_type (spell | item | class_ability) for
    # composite de-duplication with buffs_remove { id, source_type }.
    module ActiveBuffResolver
      UNIT_TO_HOURS = {
        "hours"   => 1.0,
        "minutes" => 1.0 / 60.0,
        "rounds"  => 1.0 / 600.0,
      }.freeze

      ALLOWED_BUFF_TARGETS = %w[
        ac speed saves attack damage
        strength dexterity constitution intelligence wisdom charisma
      ].freeze

      module_function

      # @param log [Object,#log!] optional pipeline log (DungeonMaster::Log)
      # @param buff_add_spec [Hash] full buffs_add row for class_ability adjudicated fields
      def resolve(source_id:, source_type:, adventure:, sheet:, explicit: {}, buff_add_spec: {}, log: nil)
        current_game_hours = current_hours(adventure)

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
            buff_add_spec: buff_add_spec,
            log: log
          )
        else
          log_warn(log, "[ActiveBuffResolver] Unknown source_type '#{source_type}' for '#{source_id}' — skipped")
          []
        end
      end

      def current_hours(adventure)
        Utilities::GameClock.absolute_hours(adventure.time_context)
      end

      def resolve_spell(source_id, sheet:, current_game_hours:, log: nil)
        defn = SpellDefinition.find_by(id: source_id)
        unless defn
          log_warn(log, "[ActiveBuffResolver] SpellDefinition '#{source_id}' not found — skipped")
          return []
        end

        caster_level = sheet.level.to_i
        duration_hours = compute_duration_hours(defn.duration_formula, level: caster_level)
        expires_at = duration_hours ? current_game_hours + duration_hours : nil

        build_entries(
          source_id,
          "spell",
          filter_effects(Array(defn.effects)),
          expires_at: expires_at,
          caster_level: caster_level
        )
      end

      def resolve_item(source_id, current_game_hours:, log: nil)
        defn = ItemDefinition.find_by(id: source_id)
        unless defn
          log_warn(log, "[ActiveBuffResolver] ItemDefinition '#{source_id}' not found — skipped")
          return []
        end

        formula = (defn.properties || {})["duration_formula"]
        duration_hours = compute_duration_hours(formula, level: nil)
        expires_at = duration_hours ? current_game_hours + duration_hours : nil

        build_entries(
          source_id,
          "item",
          filter_effects(Array(defn.effects)),
          expires_at: expires_at,
          caster_level: nil
        )
      end

      def resolve_class_ability(source_id, sheet:, current_game_hours:, buff_add_spec:, log: nil)
        buff_add_spec = buff_add_spec.deep_stringify_keys if buff_add_spec.is_a?(Hash)
        defn = ClassAbilityDefinition.find_by(id: source_id)
        unless defn
          log_warn(log, "[ActiveBuffResolver] ClassAbilityDefinition '#{source_id}' not found — skipped")
          return []
        end

        unless sheet.respond_to?(:class_ability_definitions)
          log_warn(log, "[ActiveBuffResolver] class_ability '#{source_id}' sheet has no class abilities — skipped")
          return []
        end

        unless sheet.class_ability_definitions.exists?(id: source_id.to_s)
          log_warn(log, "[ActiveBuffResolver] class_ability '#{source_id}' not on adventure sheet — skipped")
          return []
        end

        catalog = filter_effects(Array(defn.effects))
        adjudicated = normalize_adjudicated_effects(buff_add_spec["adjudicated_effects"], log: log)
        merged = catalog + adjudicated

        if merged.empty?
          log_warn(log, "[ActiveBuffResolver] class_ability '#{source_id}' has no catalog or adjudicated effects — skipped")
          return []
        end

        duration_hours = if buff_add_spec["adjudicated_duration_hours"].present?
                           buff_add_spec["adjudicated_duration_hours"].to_f
                         else
                           compute_duration_hours(defn.duration_formula, level: sheet.level.to_i)
                         end
        expires_at = duration_hours ? current_game_hours + duration_hours : nil

        build_entries(
          source_id,
          "class_ability",
          merged,
          expires_at: expires_at,
          caster_level: sheet.level.to_i
        )
      end

      def compute_duration_hours(formula, level:)
        return nil unless formula.is_a?(Hash)

        multiplier = UNIT_TO_HOURS[formula["unit"]]
        return nil unless multiplier

        return formula["fixed"].to_f * multiplier if fixed_duration?(formula)

        return formula["per_level"].to_f * level * multiplier if per_level_duration?(formula, level)

        nil
      end

      def filter_effects(effects)
        effects.select do |effect|
          next false unless effect.is_a?(Hash)

          ALLOWED_BUFF_TARGETS.include?(effect["target"].to_s)
        end
      end

      def normalize_adjudicated_effects(raw, log: nil)
        Array(raw).filter_map do |effect|
          unless effect.is_a?(Hash)
            log_warn(log, "[ActiveBuffResolver] adjudicated_effects entry must be a Hash — skipped")
            next
          end
          h = effect.deep_stringify_keys
          target = h["target"].to_s
          unless ALLOWED_BUFF_TARGETS.include?(target)
            log_warn(log, "[ActiveBuffResolver] adjudicated effect dropped unknown target '#{target}'")
            next
          end
          bonus_type = h["bonusType"] || h["bonus_type"]
          unless bonus_type.present?
            log_warn(log, "[ActiveBuffResolver] adjudicated effect dropped missing bonusType for target '#{target}'")
            next
          end
          if (camel_formula = h["bonusFormula"]).is_a?(Hash)
            h["bonus_formula"] = camel_formula.deep_stringify_keys
          elsif h["bonus_formula"].is_a?(Hash)
            h["bonus_formula"] = h["bonus_formula"].deep_stringify_keys
          end

          has_formula = h["bonus_formula"].is_a?(Hash)
          bonus_blank = !h.key?("bonus") || h["bonus"].nil? || (h["bonus"].is_a?(String) && h["bonus"].strip.empty?)
          unless has_formula || !bonus_blank
            log_warn(log, "[ActiveBuffResolver] adjudicated effect dropped missing bonus/bonus_formula for target '#{target}'")
            next
          end

          h["bonusType"] = bonus_type
          h["target"] = target
          h
        end
      end

      def build_entries(source_id, buff_source_type, effects, expires_at:, caster_level: nil)
        entries = []

        effects.each do |effect|
          next unless effect.is_a?(Hash)

          target = effect["target"].to_s
          next unless target.present?

          bonus_type = effect["bonusType"] || effect["bonus_type"]
          next unless bonus_type.present?

          value = resolve_bonus_value(effect, caster_level: caster_level)
          next unless value && value.nonzero?

          reserved = %w[type bonusType bonus_type target bonus bonus_formula]
          meta = effect.reject { |k, _| reserved.include?(k) }

          entries << ActiveBuffEntry.new(
            source: source_id,
            source_type: buff_source_type,
            bonus_type: bonus_type,
            target: target,
            value: value,
            expires_at_game_hours: expires_at,
            meta: meta.presence
          ).to_h
        end

        entries
      end

      def resolve_bonus_value(effect, caster_level: nil)
        raw = effect["bonus"]

        return raw if raw.is_a?(Integer)

        return raw.to_i if raw.is_a?(Float)

        return formula_bonus_value(effect["bonus_formula"], caster_level) if effect["bonus_formula"].is_a?(Hash)

        return Integer(raw, 10) if raw.is_a?(String) && raw.match?(/\A-?\d+\z/)

        nil
      end

      def fixed_duration?(formula)
        formula.key?("fixed")
      end

      def per_level_duration?(formula, level)
        formula.key?("per_level") && level
      end

      def formula_bonus_value(bonus_formula, caster_level)
        base = bonus_formula["base"].to_i
        return base unless scales_with_caster_level?(bonus_formula, caster_level)

        scaled_bonus = base + (caster_level / bonus_formula["per_n_cl"].to_i)
        capped_bonus_for_formula(scaled_bonus, bonus_formula)
      end

      def scales_with_caster_level?(bonus_formula, caster_level)
        caster_level && bonus_formula["per_n_cl"].to_i > 0
      end

      def capped_bonus_for_formula(value, bonus_formula)
        bonus_formula["max"] ? [value, bonus_formula["max"].to_i].min : value
      end

      def log_warn(log, msg)
        if log&.respond_to?(:log!)
          log.log!(:warn, msg)
        else
          Rails.logger.warn(msg)
        end
      end
    end
  end
end
