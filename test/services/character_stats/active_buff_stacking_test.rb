# frozen_string_literal: true

require "test_helper"

class ActiveBuffStackingTest < ActiveSupport::TestCase
  test "same bonus_type stacks by highest only" do
    buffs = [
      { "target" => "ac", "bonus_type" => "morale", "value" => 2 },
      { "target" => "ac", "bonus_type" => "morale", "value" => 4 },
    ]
    assert_equal 4, CharacterStats::ActiveBuffStacking.stacked_value_for_target(buffs, "ac")
  end

  test "distinct bonus_types sum" do
    buffs = [
      { "target" => "ac", "bonus_type" => "morale", "value" => 2 },
      { "target" => "ac", "bonus_type" => "deflection", "value" => 3 },
    ]
    assert_equal 5, CharacterStats::ActiveBuffStacking.stacked_value_for_target(buffs, "ac")
  end

  test "saves target aggregates" do
    buffs = [
      { "target" => "saves", "bonus_type" => "morale", "value" => 2 },
      { "target" => "saves", "bonus_type" => "resistance", "value" => 1 },
    ]
    assert_equal 3, CharacterStats::ActiveBuffStacking.stacked_value_for_target(buffs, "saves")
  end
end
