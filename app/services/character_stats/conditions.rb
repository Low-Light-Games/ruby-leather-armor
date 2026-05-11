# frozen_string_literal: true

module CharacterStats
  module Conditions
    DEFINITIONS = {
      "fatigued" => {
        ability_penalties: { "strength" => -2, "dexterity" => -2 },
        restrictions: %w[cannot_run cannot_charge],
        upgrades_to: "exhausted",
      },
      "exhausted" => {
        ability_penalties: { "strength" => -6, "dexterity" => -6 },
        speed_multiplier: 0.5,
        restrictions: %w[cannot_run cannot_charge],
      },
      "shaken" => {
        roll_penalties: { "attack" => -2, "saves" => -2, "skills" => -2, "ability_checks" => -2 },
        upgrades_to: "frightened",
      },
      "frightened" => {
        roll_penalties: { "attack" => -2, "saves" => -2, "skills" => -2, "ability_checks" => -2 },
        restrictions: %w[must_flee],
        upgrades_to: "panicked",
      },
      "panicked" => {
        roll_penalties: { "attack" => -2, "saves" => -2, "skills" => -2, "ability_checks" => -2 },
        restrictions: %w[must_flee drop_held_items],
      },
      "sickened" => {
        roll_penalties: { "attack" => -2, "damage" => -2, "saves" => -2, "skills" => -2, "ability_checks" => -2 },
      },
      "nauseated" => {
        restrictions: %w[can_only_move],
      },
      "entangled" => {
        roll_penalties: { "attack" => -2 },
        ability_penalties: { "dexterity" => -4 },
      },
      "prone" => {
        roll_penalties: { "melee_attack" => -4 },
        ac_modifiers: { "melee" => -4, "ranged" => 4 },
      },
      "blinded" => {
        ac_modifiers: { "all" => -2 },
        restrictions: %w[deny_dex_to_ac],
      },
      "staggered" => {
        restrictions: %w[single_action_only],
      },
      "paralyzed" => {
        restrictions: %w[cannot_act deny_dex_to_ac],
        effective_scores: { "strength" => 0, "dexterity" => 0 },
      },
      "stunned" => {
        restrictions: %w[cannot_act deny_dex_to_ac],
        ac_modifiers: { "all" => -2 },
      },
      "dazed" => {
        restrictions: %w[cannot_act],
      },
      "poisoned" => {},
      "grappled" => {
        roll_penalties: { "attack" => -2 },
        ability_penalties: { "dexterity" => -4 },
        restrictions: %w[cannot_move deny_dex_to_ac_vs_non_grappler],
      },
      "fled" => {},
      "surrendered" => {},
      "dead" => {},
      "disabled" => {},
      "petrified" => {
        restrictions: %w[cannot_act deny_dex_to_ac],
      },
      "stabilized" => {},
    }.freeze

    VALID_CONDITIONS = DEFINITIONS.keys.freeze

    def self.valid?(name)
      VALID_CONDITIONS.include?(name.to_s)
    end

    def self.ability_penalties(active_conditions)
      combined = {}
      Array(active_conditions).each do |cond_name|
        defn = DEFINITIONS[cond_name]
        next unless defn

        (defn[:ability_penalties] || {}).each do |ability, penalty|
          combined[ability] = (combined[ability] || 0) + penalty
        end
      end
      combined
    end

    def self.effective_scores(active_conditions)
      overrides = {}
      Array(active_conditions).each do |cond_name|
        defn = DEFINITIONS[cond_name]
        next unless defn

        (defn[:effective_scores] || {}).each do |ability, value|
          current = overrides[ability]
          overrides[ability] = current ? [current, value].min : value
        end
      end
      overrides
    end

    def self.speed_multiplier(active_conditions)
      multiplier = 1.0
      Array(active_conditions).each do |cond_name|
        defn = DEFINITIONS[cond_name]
        next unless defn

        if defn[:speed_multiplier]
          multiplier = [multiplier, defn[:speed_multiplier]].min
        end
      end
      multiplier
    end

    def self.restrictions(active_conditions)
      Array(active_conditions).flat_map do |cond_name|
        defn = DEFINITIONS[cond_name]
        defn ? (defn[:restrictions] || []) : []
      end.uniq
    end

    def self.upgrade(current_conditions, adding)
      current = current_conditions.dup
      defn = DEFINITIONS[adding]

      if current.include?(adding) && defn && defn[:upgrades_to]
        current.delete(adding)
        upgraded = defn[:upgrades_to]
        current << upgraded unless current.include?(upgraded)
      else
        current << adding unless current.include?(adding)
      end

      current
    end
  end
end
