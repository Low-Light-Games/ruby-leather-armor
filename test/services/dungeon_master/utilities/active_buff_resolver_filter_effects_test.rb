# frozen_string_literal: true

require "test_helper"

class ActiveBuffResolverFilterEffectsTest < ActiveSupport::TestCase
  test "filter_effects drops unknown targets and keeps allow-listed targets" do
    effects = [
      { "target" => "foo", "bonusType" => "morale", "bonus" => 1 },
      { "target" => "ac", "bonusType" => "deflection", "bonus" => 2 },
    ]
    filtered = DungeonMaster::Utilities::ActiveBuffResolver.filter_effects(effects)

    assert_equal 1, filtered.size
    assert_equal "ac", filtered.first["target"]
  end
end
