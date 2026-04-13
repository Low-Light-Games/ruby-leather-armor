require "rails_helper"

RSpec.describe DungeonMaster::CharacterBlock, type: :model do
  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let(:sheet) do
    create(:adventure_sheet,
      adventure: adventure,
      strength: 14, dexterity: 12, constitution: 13,
      intelligence: 10, wisdom: 11, charisma: 8,
      race: "human", character_class: "fighter", level: 1).tap(&:recompute_derived_stats!)
  end

  context "with no conditions" do
    it "does not include Active Conditions line in full block" do
      text = described_class.full(sheet)
      expect(text).not_to include("Active Conditions")
    end

    it "does not include Active Conditions line in combat block" do
      text = described_class.for(sheet, category: "combat")
      expect(text).not_to include("Active Conditions")
    end

    it "does not include Active Conditions line in social block" do
      text = described_class.social(sheet)
      expect(text).not_to include("Active Conditions")
    end

    it "does not include Active Conditions line in traversal block" do
      text = described_class.traversal(sheet)
      expect(text).not_to include("Active Conditions")
    end
  end

  context "when fatigued" do
    before { sheet.update_column(:conditions, ["fatigued"]) }

    it "includes Active Conditions in full block" do
      text = described_class.full(sheet)
      expect(text).to include("Active Conditions: fatigued")
    end

    it "includes Active Conditions in combat block" do
      text = described_class.for(sheet, category: "combat")
      expect(text).to include("Active Conditions: fatigued")
    end

    it "includes Active Conditions in social block" do
      text = described_class.social(sheet)
      expect(text).to include("Active Conditions: fatigued")
    end

    it "includes Active Conditions in traversal block" do
      text = described_class.traversal(sheet)
      expect(text).to include("Active Conditions: fatigued")
    end
  end

  context "with multiple conditions" do
    before { sheet.update_column(:conditions, ["fatigued", "sickened"]) }

    it "lists all conditions comma-separated" do
      text = described_class.full(sheet)
      expect(text).to include("Active Conditions: fatigued, sickened")
    end
  end
end
