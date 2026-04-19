# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::PromptRenderer do
  describe ".render_with_user_message" do
    it "splits templates that define a user message section" do
      system_prompt, user_message = described_class.render_with_user_message("macro_narrative_update",
        story_intro: "Hook",
        story_summary: "Summary",
        what_happened: "Latest events")

      expect(system_prompt).to be_present
      expect(user_message).to be_present
    end

    it "raises when the template has no user message separator" do
      expect {
        described_class.render_with_user_message("micro_context_meta_update",
          what_happened: "Latest events",
          scene_summary: "Summary",
          context_wishes: [])
      }.to raise_error(ArgumentError, /does not define/)
    end
  end
end
