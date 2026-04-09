# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdventureMessage, type: :model do
  describe "scopes" do
    let(:adventure) { create(:adventure) }

    it "newest_first orders by created_at descending" do
      old = create(:adventure_message, adventure: adventure, role: "player", message_type: "narrative")
      old.update_column(:created_at, 2.days.ago)
      new = create(:adventure_message, adventure: adventure, role: "player", message_type: "narrative")
      expect(adventure.adventure_messages.newest_first.first).to eq(new)
      expect(adventure.adventure_messages.newest_first.last).to eq(old)
    end

    it "from_players filters to player role" do
      create(:adventure_message, adventure: adventure, role: "dm", message_type: "narrative")
      player = create(:adventure_message, adventure: adventure, role: "player", message_type: "narrative")
      expect(adventure.adventure_messages.from_players).to contain_exactly(player)
    end

    it "for_message_types filters by message_type list" do
      roll = create(:adventure_message, adventure: adventure, role: "dm", message_type: "roll_request")
      create(:adventure_message, adventure: adventure, role: "player", message_type: "narrative")
      expect(adventure.adventure_messages.for_message_types(%w[roll_request])).to contain_exactly(roll)
    end
  end
end
