require "rails_helper"

RSpec.describe Sheet, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should have_many(:sheet_feats).dependent(:destroy) }
    it { should have_many(:sheet_spells).dependent(:destroy) }
    it { should have_many(:sheet_items).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:strength) }
    it { should validate_presence_of(:dexterity) }
    it { should validate_presence_of(:constitution) }
    it { should validate_presence_of(:intelligence) }
    it { should validate_presence_of(:wisdom) }
    it { should validate_presence_of(:charisma) }
    it { should validate_numericality_of(:level).only_integer.is_greater_than(0) }
  end

  describe "factory" do
    it "builds a valid sheet" do
      expect(build(:sheet)).to be_valid
    end
  end
end
