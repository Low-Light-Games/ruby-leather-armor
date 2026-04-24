# frozen_string_literal: true

require "test_helper"

class ClassAbilityDefinitionTest < ActiveSupport::TestCase
  setup do
    ClassAbilityDefinition.find_or_create_by!(id: "rage") do |d|
      d.name = "Rage"
      d.pf1e_class = "barbarian"
      d.summary = "Rage summary"
    end
    ClassAbilityDefinition.find_or_create_by!(id: "greater_rage") do |d|
      d.name = "Greater Rage"
      d.pf1e_class = "barbarian"
      d.summary = "Greater rage summary"
    end
    ClassAbilityDefinition.find_or_create_by!(id: "mighty_rage") do |d|
      d.name = "Mighty Rage"
      d.pf1e_class = "barbarian"
      d.summary = "Mighty rage summary"
    end
  end

  test "applicable_for_character_sheet returns rage only at level 1" do
    sheet = Struct.new(:character_class, :level).new("barbarian", 1)
    ids = ClassAbilityDefinition.applicable_for_character_sheet(sheet).pluck(:id).sort
    assert_equal %w[rage], ids
  end

  test "applicable_for_character_sheet adds greater rage at 11" do
    sheet = Struct.new(:character_class, :level).new("barbarian", 11)
    ids = ClassAbilityDefinition.applicable_for_character_sheet(sheet).pluck(:id).sort
    assert_equal %w[greater_rage rage], ids
  end

  test "applicable_for_character_sheet adds mighty rage at 20" do
    sheet = Struct.new(:character_class, :level).new("barbarian", 20)
    ids = ClassAbilityDefinition.applicable_for_character_sheet(sheet).pluck(:id).sort
    assert_equal %w[greater_rage mighty_rage rage], ids
  end

  test "applicable_for_character_sheet is empty without class" do
    sheet = Struct.new(:character_class, :level).new(nil, 5)
    assert ClassAbilityDefinition.applicable_for_character_sheet(sheet).none?
  end

  test "AdventureSheet#class_ability_definitions matches lookup" do
    user = User.create!(
      email: "cab-#{SecureRandom.hex(4)}@example.com",
      password: "password123456",
      onboarding_state: "completed"
    )
    story = Story.create!(title: "Cab", preview: "P", premise: "Pr")
    adventure = Adventure.create!(user: user, story: story)
    adv_sheet = adventure.adventure_sheets.create!(
      name: "Grulk",
      strength: 16, intelligence: 8, dexterity: 14, constitution: 14, wisdom: 10, charisma: 10,
      character_class: "barbarian",
      level: 1
    )

    expected = ClassAbilityDefinition.applicable_for_character_sheet(adv_sheet).pluck(:id).sort
    assert_equal expected, adv_sheet.class_ability_definitions.pluck(:id).sort
  end
end
