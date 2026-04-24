# frozen_string_literal: true

require "test_helper"

module Adventures
  class ClassAbilitySyncTest < ActiveSupport::TestCase
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

      @user = User.create!(
        email: "class-ability-sync-#{SecureRandom.hex(4)}@example.com",
        password: "password123456",
        onboarding_state: "completed"
      )
      @story = Story.create!(title: "Sync Story", preview: "Preview", premise: "Premise")
      @adventure = Adventure.create!(user: @user, story: @story)
      @sheet = @adventure.adventure_sheets.create!(
        name: "Grulk",
        strength: 16, intelligence: 8, dexterity: 14, constitution: 14, wisdom: 10, charisma: 10,
        character_class: "barbarian",
        level: 1
      )
    end

    test "sync links only rage for level 1 barbarian" do
      ClassAbilitySync.sync!(@sheet)
      ids = @sheet.reload.class_ability_definitions.pluck(:id).sort
      assert_equal %w[rage], ids
    end

    test "sync adds greater rage at level 11" do
      @sheet.update!(level: 11)
      ClassAbilitySync.sync!(@sheet)
      ids = @sheet.reload.class_ability_definitions.pluck(:id).sort
      assert_equal %w[greater_rage rage], ids
    end

    test "sync adds mighty rage at level 20" do
      @sheet.update!(level: 20)
      ClassAbilitySync.sync!(@sheet)
      ids = @sheet.reload.class_ability_definitions.pluck(:id).sort
      assert_equal %w[greater_rage mighty_rage rage], ids
    end

    test "sync is a no-op when character_class is blank" do
      @sheet.update!(character_class: nil)
      ClassAbilitySync.sync!(@sheet)
      assert_empty @sheet.reload.class_ability_definitions
    end
  end
end
