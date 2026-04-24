# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # Filtering and row materialization for persisted active_buff JSON.
    module ActiveBuffEffectRows
      ALLOWED_BUFF_TARGETS = %w[
        ac speed saves attack damage
        strength dexterity constitution intelligence wisdom charisma
      ].freeze

      module_function

      def filter_effects(effects)
        effects.select do |effect|
          next false unless effect.is_a?(Hash)

          ALLOWED_BUFF_TARGETS.include?(effect["target"].to_s)
        end
      end

      def normalize_adjudicated_effects(raw, log: nil)
        Array(raw).filter_map do |effect|
          unless effect.is_a?(Hash)
            PipelineWarn.emit(log, "[ActiveBuffResolver] adjudicated_effects entry must be a Hash — skipped")
            next
          end
          h = effect.deep_stringify_keys
          target = h["target"].to_s
          unless ALLOWED_BUFF_TARGETS.include?(target)
            PipelineWarn.emit(log, "[ActiveBuffResolver] adjudicated effect dropped unknown target '#{target}'")
            next
          end
          bonus_type = h["bonusType"] || h["bonus_type"]
          unless bonus_type.present?
            PipelineWarn.emit(log, "[ActiveBuffResolver] adjudicated effect dropped missing bonusType for target '#{target}'")
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
            PipelineWarn.emit(log, "[ActiveBuffResolver] adjudicated effect dropped missing bonus/bonus_formula for target '#{target}'")
            next
          end

          h["bonusType"] = bonus_type
          h["target"] = target
          h
        end
      end

      def build_buff_rows(source_id, buff_source_type, effects, expires_at:, caster_level: nil)
        entries = []

        effects.each do |effect|
          next unless effect.is_a?(Hash)

          target = effect["target"].to_s
          next unless target.present?

          bonus_type = effect["bonusType"] || effect["bonus_type"]
          next unless bonus_type.present?

          value = ActiveBuffResolverNumbers.bonus_numeric_from_effect(effect, caster_level: caster_level)
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
    end
  end
end
