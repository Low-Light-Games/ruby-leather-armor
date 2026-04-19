# frozen_string_literal: true

require "rails_helper"

# Verifies that death_type set on PipelineContext flows through
# NarratePromptView and surfaces in the rendered narrate.text.erb prompt.
RSpec.describe "death-aware narration prompt", type: :service do
  def build_view(death_type:)
    ctx = DungeonMaster::PipelineContext.new(
      combined_seed: "The goblin strikes.",
      dm_brief:      nil,
      player_action: "Attack the goblin.",
      death_type:    death_type
    )

    DungeonMaster::Narrative::NarratePromptView.new(
      pipeline_context:   ctx,
      loop:               nil,
      combat_context:     {},
      time_context:       {},
      pacing_text:        "",
      directed_play_text: ""
    )
  end

  describe "NarratePromptView#death_type" do
    it "returns nil when death_type is absent" do
      view = build_view(death_type: nil)
      expect(view.death_type).to be_nil
    end

    it "returns :player_death when set" do
      view = build_view(death_type: :player_death)
      expect(view.death_type).to eq(:player_death)
    end

    it "returns :player_incapacitated when set" do
      view = build_view(death_type: :player_incapacitated)
      expect(view.death_type).to eq(:player_incapacitated)
    end
  end

  describe "NarratePromptView#directed_play_text" do
    let(:directed_text) { "=== DIRECTED PLAY STYLE ===" }

    def build_view_with_directed(death_type:)
      ctx = DungeonMaster::PipelineContext.new(
        combined_seed: "The goblin strikes.",
        dm_brief:      nil,
        player_action: "Attack the goblin.",
        death_type:    death_type
      )
      DungeonMaster::Narrative::NarratePromptView.new(
        pipeline_context:   ctx,
        loop:               nil,
        combat_context:     {},
        time_context:       {},
        pacing_text:        "",
        directed_play_text: directed_text
      )
    end

    it "returns the directed play text when no death_type" do
      view = build_view_with_directed(death_type: nil)
      expect(view.directed_play_text).to eq(directed_text)
    end

    it "suppresses directed play text for :player_death" do
      view = build_view_with_directed(death_type: :player_death)
      expect(view.directed_play_text).to eq("")
    end

    it "suppresses directed play text for :player_incapacitated" do
      view = build_view_with_directed(death_type: :player_incapacitated)
      expect(view.directed_play_text).to eq("")
    end
  end

  describe "narrate.text.erb rendering" do
    it "omits the death block when death_type is nil" do
      view = build_view(death_type: nil)
      prompt = DungeonMaster::PromptRenderer.render("narrate", narrate_view: view)
      expect(prompt).not_to include("CHARACTER DEATH")
      expect(prompt).not_to include("CHARACTER INCAPACITATED")
    end

    it "includes the death block for :player_death" do
      view = build_view(death_type: :player_death)
      prompt = DungeonMaster::PromptRenderer.render("narrate", narrate_view: view)
      expect(prompt).to include("=== CHARACTER DEATH ===")
      expect(prompt).not_to include("CHARACTER INCAPACITATED")
    end

    it "includes the incapacitated block for :player_incapacitated" do
      view = build_view(death_type: :player_incapacitated)
      prompt = DungeonMaster::PromptRenderer.render("narrate", narrate_view: view)
      expect(prompt).to include("=== CHARACTER INCAPACITATED ===")
      expect(prompt).not_to include("CHARACTER DEATH")
    end

    it "death block appears before the JSON instruction" do
      view = build_view(death_type: :player_death)
      prompt = DungeonMaster::PromptRenderer.render("narrate", narrate_view: view)
      death_pos = prompt.index("CHARACTER DEATH")
      json_pos  = prompt.index("Respond ONLY with valid JSON")
      expect(death_pos).to be < json_pos
    end

    it "renders canonical combat facts and lethal constraints for hostiles" do
      ctx = DungeonMaster::PipelineContext.new(
        combined_seed: "You wound the first orc for 3 piercing damage.",
        dm_brief: nil,
        player_action: "I slash at the nearest orc."
      )
      view = DungeonMaster::Narrative::NarratePromptView.new(
        pipeline_context: ctx,
        loop: nil,
        combat_context: {
          "active" => true,
          "participants" => [
            { "name" => "Player", "type" => "player", "hp" => 22, "max_hp" => 22 },
            { "name" => "Orc 1", "type" => "npc", "hp" => 2, "max_hp" => 5 },
            { "name" => "Orc 2", "type" => "npc", "hp" => 5, "max_hp" => 5 }
          ]
        },
        time_context: {},
        pacing_text: "",
        directed_play_text: ""
      )

      prompt = DungeonMaster::PromptRenderer.render("narrate", narrate_view: view)
      expect(prompt).to include("=== CANONICAL COMBAT FACTS (authoritative current hostile state) ===")
      expect(prompt).to include("\"any_hostile_alive\":true")
      expect(prompt).to include("do not narrate all hostiles as dead")
      expect(prompt).to include("Do not introduce extra hostiles")
    end
  end
end
