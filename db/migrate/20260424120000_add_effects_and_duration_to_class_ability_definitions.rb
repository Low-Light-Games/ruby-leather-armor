# frozen_string_literal: true

# Adds spell-like catalog columns for class abilities. Seeds exemplar effects for
# rage tree, inspire courage, and leaves fighting_defensively empty for adjudicated_effects.
# Rage duration v1: fixed 10 rounds (placeholder until Con-based formula exists).
class AddEffectsAndDurationToClassAbilityDefinitions < ActiveRecord::Migration[7.1]
  RAGE_DURATION = { "unit" => "rounds", "fixed" => 10 }.freeze

  # PF1e-style morale bonuses; AC penalty is morale -2 on ac target.
  RAGE_EFFECTS = [
    { "target" => "strength", "bonusType" => "morale", "bonus" => 2 },
    { "target" => "constitution", "bonusType" => "morale", "bonus" => 2 },
    { "target" => "saves", "bonusType" => "morale", "bonus" => 2 },
    { "target" => "ac", "bonusType" => "morale", "bonus" => -2 },
  ].freeze

  GREATER_RAGE_EFFECTS = [
    { "target" => "strength", "bonusType" => "morale", "bonus" => 4 },
    { "target" => "constitution", "bonusType" => "morale", "bonus" => 4 },
    { "target" => "saves", "bonusType" => "morale", "bonus" => 3 },
    { "target" => "ac", "bonusType" => "morale", "bonus" => -2 },
  ].freeze

  MIGHTY_RAGE_EFFECTS = [
    { "target" => "strength", "bonusType" => "morale", "bonus" => 6 },
    { "target" => "constitution", "bonusType" => "morale", "bonus" => 6 },
    { "target" => "saves", "bonusType" => "morale", "bonus" => 4 },
    { "target" => "ac", "bonusType" => "morale", "bonus" => -2 },
  ].freeze

  # Minimal v1: competence to attack and damage (PF1 inspire courage core combat bonuses).
  INSPIRE_COURAGE_EFFECTS = [
    { "target" => "attack", "bonusType" => "competence", "bonus" => 1 },
    { "target" => "damage", "bonusType" => "competence", "bonus" => 1 },
  ].freeze

  INSPIRE_DURATION = { "unit" => "rounds", "fixed" => 100 }.freeze

  def up
    add_column :class_ability_definitions, :effects, :jsonb, null: false, default: []
    add_column :class_ability_definitions, :duration_formula, :jsonb

    say_with_time "Seeding class_ability_definitions effects" do
      ClassAbilityDefinition.reset_column_information
      update_row!("rage", RAGE_EFFECTS, RAGE_DURATION)
      update_row!("greater_rage", GREATER_RAGE_EFFECTS, RAGE_DURATION)
      update_row!("mighty_rage", MIGHTY_RAGE_EFFECTS, RAGE_DURATION)
      update_row!("inspire_courage", INSPIRE_COURAGE_EFFECTS, INSPIRE_DURATION)
      ensure_stub!("fighting_defensively", "Fighting Defensively", "fighter",
        "Fight defensively to trade offense for AC; use adjudicated_effects when applying as a buff.")
    end
  end

  def down
    remove_column :class_ability_definitions, :duration_formula
    remove_column :class_ability_definitions, :effects
  end

  private

  def update_row!(id, effects, duration_formula)
    row = ClassAbilityDefinition.find_by(id: id)
    return unless row

    row.update!(effects: effects, duration_formula: duration_formula)
  end

  def ensure_stub!(id, name, pf1e_class, summary)
    ClassAbilityDefinition.find_or_initialize_by(id: id).tap do |row|
      row.name = name
      row.pf1e_class = pf1e_class
      row.summary = summary
      row.effects = []
      row.duration_formula = nil
      row.save!
    end
  end
end
