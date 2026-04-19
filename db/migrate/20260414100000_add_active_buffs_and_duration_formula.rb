# frozen_string_literal: true

class AddActiveBuffsAndDurationFormula < ActiveRecord::Migration[7.1]
  def change
    # Sheet-level timed bonus entries: spells, potions, class features.
    # Each entry: { source, bonus_type, target, value, expires_at_game_hours }
    add_column :adventure_sheets, :active_buffs, :jsonb, null: false, default: []

    # Structured duration formula for spell definitions so ActiveBuffResolver
    # can compute expires_at_game_hours deterministically without AI math.
    # Format: { "unit": "hours"|"minutes"|"rounds", "per_level": N } or { "unit": ..., "fixed": N }
    add_column :spell_definitions, :duration_formula, :jsonb
  end
end
