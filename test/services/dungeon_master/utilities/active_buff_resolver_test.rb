# frozen_string_literal: true

require "test_helper"
require "ostruct"

class ActiveBuffResolverTest < ActiveSupport::TestCase
  test "build_entries parses strict integer bonus strings" do
    entries = DungeonMaster::Utilities::ActiveBuffResolver.build_entries(
      "spell_x",
      "spell",
      [{ "target" => "ac", "bonusType" => "deflection", "bonus" => "3" }],
      expires_at: 1.0,
      caster_level: 5
    )

    assert_equal 1, entries.size
    assert_equal 3, entries.first["value"]
  end

  test "build_entries rejects non-numeric bonus strings" do
    entries = DungeonMaster::Utilities::ActiveBuffResolver.build_entries(
      "spell_x",
      "spell",
      [{ "target" => "ac", "bonusType" => "deflection", "bonus" => "12abc" }],
      expires_at: 1.0,
      caster_level: 5
    )

    assert_empty entries
  end

  test "normalize_adjudicated_effects drops effects with no bonus or formula" do
    out = DungeonMaster::Utilities::ActiveBuffResolver.normalize_adjudicated_effects(
      [{ "target" => "ac", "bonusType" => "dodge" }]
    )

    assert_empty out
  end

  test "normalize_adjudicated_effects accepts bonusFormula camelCase" do
    out = DungeonMaster::Utilities::ActiveBuffResolver.normalize_adjudicated_effects(
      [{
        "target" => "ac",
        "bonusType" => "dodge",
        "bonusFormula" => { "base" => 1, "per_n_cl" => 0 },
      }]
    )

    assert_equal 1, out.size
    assert_equal({ "base" => 1, "per_n_cl" => 0 }, out.first["bonus_formula"])
  end

  test "compute_duration_hours returns nil for unknown unit" do
    hours = DungeonMaster::Utilities::ActiveBuffResolver.compute_duration_hours(
      { "unit" => "weeks", "fixed" => 1 },
      level: 5
    )

    assert_nil hours
  end

  test "compute_duration_hours applies fixed rounds" do
    hours = DungeonMaster::Utilities::ActiveBuffResolver.compute_duration_hours(
      { "unit" => "rounds", "fixed" => 600 },
      level: 5
    )

    assert_in_delta 1.0, hours, 1e-9
  end

  test "compute_duration_hours per_level requires level" do
    assert_nil DungeonMaster::Utilities::ActiveBuffResolver.compute_duration_hours(
      { "unit" => "rounds", "per_level" => 1 },
      level: nil
    )
  end

  test "resolve_spell builds entries from fixture-like spell definition" do
    sid = "active_buff_resolver_test_spell"
    SpellDefinition.find_by(id: sid)&.destroy

    SpellDefinition.create!(
      id: sid,
      name: "Test Buff",
      school: "transmutation",
      duration_formula: { "unit" => "rounds", "fixed" => 1 },
      effects: [{ "target" => "ac", "bonusType" => "deflection", "bonus" => 1 }]
    )

    adventure = OpenStruct.new(time_context: { "adventure_day" => 1, "current_hour" => 0.0 })
    sheet = OpenStruct.new(level: 3)

    entries = DungeonMaster::Utilities::ActiveBuffResolver.resolve(
      source_id: sid,
      source_type: "spell",
      adventure: adventure,
      sheet: sheet,
      log: nil
    )

    assert_equal 1, entries.size
    assert_equal sid, entries.first["source"]
    assert_equal "spell", entries.first["source_type"]
    assert_equal 1, entries.first["value"]
  ensure
    SpellDefinition.find_by(id: sid)&.destroy
  end
end
