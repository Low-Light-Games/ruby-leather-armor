# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # Resolves a buff source into one or more active_buffs entries ready to be
    # persisted on an AdventureSheet.
    #
    # Each returned entry:
    #   {
    #     "source"               => String,   # source ID (de-dup key)
    #     "bonus_type"           => String,   # PF1e bonus type token
    #     "target"               => String,   # routing key: "ac", "speed", "saves", …
    #     "value"                => Integer,  # resolved numeric bonus
    #     "expires_at_game_hours"=> Float|nil # absolute game-hour or nil = no expiry
    #   }
    #
    # Source types
    # ────────────
    #   "spell"         — looks up SpellDefinition by id; uses duration_formula + effects
    #   "item"          — looks up ItemDefinition by id; uses properties["duration_formula"] + effects
    #   "class_feature" — AI supplies explicit: bonus_type, target, value, duration_hours (optional)
    #
    # The resolver returns ALL bonus components regardless of target. The calculator
    # layer (CombatCalculator for "ac", Calculator for "speed") decides what to apply;
    # unknown targets are stored and ignored until a handler is added — zero changes
    # needed here or in Mutations for future expansions.
    #
    # Stacking rule (enforced by calculators, not here):
    #   same bonus_type  → highest value wins (replacement)
    #   different types  → all values stack (additive)
    #
    # TODO: caster level is assumed equal to sheet.level. Revisit when multiclass
    #       support is added and a character can have different caster/class levels.
    module ActiveBuffResolver
      UNIT_TO_HOURS = {
        "hours"   => 1.0,
        "minutes" => 1.0 / 60.0,
        "rounds"  => 1.0 / 600.0, # 1 round = 6 seconds; 600 rounds = 1 hour
      }.freeze

      module_function

      # @param source_id   [String]
      # @param source_type [String]  "spell" | "item" | "class_feature"
      # @param adventure   [Adventure]
      # @param sheet       [AdventureSheet]
      # @param explicit    [Hash]  only used for class_feature
      # @return [Array<Hash>]
      def resolve(source_id:, source_type:, adventure:, sheet:, explicit: {})
        current_game_hours = current_hours(adventure)

        case source_type
        when "spell"
          resolve_spell(source_id, sheet: sheet, current_game_hours: current_game_hours)
        when "item"
          resolve_item(source_id, current_game_hours: current_game_hours)
        when "class_feature"
          resolve_class_feature(source_id, explicit: explicit, current_game_hours: current_game_hours)
        else
          Rails.logger.info("[ActiveBuffResolver] Unknown source_type '#{source_type}' for '#{source_id}' — skipped")
          []
        end
      end

      # ── Helpers ──────────────────────────────────────────────────────────

      def current_hours(adventure)
        Utilities::GameClock.absolute_hours(adventure.time_context)
      end

      def resolve_spell(source_id, sheet:, current_game_hours:)
        defn = SpellDefinition.find_by(id: source_id)
        unless defn
          Rails.logger.info("[ActiveBuffResolver] SpellDefinition '#{source_id}' not found — skipped")
          return []
        end

        caster_level = sheet.level.to_i
        duration_hours = compute_duration_hours(defn.duration_formula, level: caster_level)
        expires_at = duration_hours ? current_game_hours + duration_hours : nil

        build_entries(source_id, Array(defn.effects), expires_at: expires_at, caster_level: caster_level)
      end

      def resolve_item(source_id, current_game_hours:)
        defn = ItemDefinition.find_by(id: source_id)
        unless defn
          Rails.logger.info("[ActiveBuffResolver] ItemDefinition '#{source_id}' not found — skipped")
          return []
        end

        formula = (defn.properties || {})["duration_formula"]
        duration_hours = compute_duration_hours(formula, level: nil)
        expires_at = duration_hours ? current_game_hours + duration_hours : nil

        build_entries(source_id, Array(defn.effects), expires_at: expires_at, caster_level: nil)
      end

      def resolve_class_feature(source_id, explicit:, current_game_hours:)
        bonus_type   = explicit["bonus_type"] || explicit[:bonus_type]
        target       = explicit["target"]      || explicit[:target]
        value        = (explicit["value"]      || explicit[:value]).to_i
        duration_h   = (explicit["duration_hours"] || explicit[:duration_hours])&.to_f

        unless bonus_type && target && value.nonzero?
          Rails.logger.info("[ActiveBuffResolver] class_feature '#{source_id}' missing bonus_type/target/value — skipped")
          return []
        end

        expires_at = duration_h ? current_game_hours + duration_h : nil

        [{
          "source"                => source_id,
          "bonus_type"            => bonus_type.to_s,
          "target"                => target.to_s,
          "value"                 => value,
          "expires_at_game_hours" => expires_at
        }]
      end

      # ── Duration ─────────────────────────────────────────────────────────

      # Returns duration in hours, or nil if no formula / no expiry.
      def compute_duration_hours(formula, level:)
        return nil unless formula.is_a?(Hash)

        unit     = formula["unit"]
        multiplier = UNIT_TO_HOURS[unit]
        return nil unless multiplier

        if formula.key?("fixed")
          formula["fixed"].to_f * multiplier
        elsif formula.key?("per_level") && level
          formula["per_level"].to_f * level * multiplier
        end
      end

      # ── Effect building ───────────────────────────────────────────────────

      def build_entries(source_id, effects, expires_at:, caster_level: nil)
        entries = []

        effects.each do |effect|
          next unless effect.is_a?(Hash)

          target = effect["target"]
          next unless target.present?

          bonus_type = effect["bonusType"] || effect["bonus_type"]
          next unless bonus_type.present?

          value = resolve_bonus_value(effect, caster_level: caster_level)
          next unless value && value.nonzero?

          # Persist all effect keys that are not already captured in the top-level
          # entry. This lets future target handlers (saves, attacks, etc.) access
          # conditional metadata (e.g. applies_vs, save_type, school) without
          # requiring a migration or resolver rewrite.
          reserved = %w[type bonusType bonus_type target bonus bonus_formula]
          meta = effect.reject { |k, _| reserved.include?(k) }

          entry = {
            "source"                => source_id,
            "bonus_type"            => bonus_type.to_s,
            "target"                => target.to_s,
            "value"                 => value,
            "expires_at_game_hours" => expires_at
          }
          entry["meta"] = meta unless meta.empty?
          entries << entry
        end

        entries
      end

      # Resolves the numeric bonus for a single effect.
      # Evaluates bonus_formula when caster_level is available.
      # Formula shape: { "base": N, "per_n_cl": D, "max": M }
      #   value = base + floor(caster_level / per_n_cl), capped at max
      def resolve_bonus_value(effect, caster_level: nil)
        raw = effect["bonus"]

        if raw.is_a?(Integer)
          raw
        elsif raw.is_a?(Float)
          raw.to_i
        elsif effect["bonus_formula"].is_a?(Hash)
          bf = effect["bonus_formula"]
          base = bf["base"].to_i
          if caster_level && bf["per_n_cl"].to_i > 0
            bonus = base + (caster_level / bf["per_n_cl"].to_i)
            bf["max"] ? [bonus, bf["max"].to_i].min : bonus
          else
            base
          end
        elsif raw.is_a?(String)
          raw.to_i
        end
      end
    end
  end
end
