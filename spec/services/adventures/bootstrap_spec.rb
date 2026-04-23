# frozen_string_literal: true

require "rails_helper"

RSpec.describe Adventures::Bootstrap, type: :service do
  let(:user)  { create(:user) }
  let(:story) { create(:story) }
  let(:sheet) { create(:sheet, user: user) }

  before do
    allow_any_instance_of(DungeonMaster::Embellisher).to receive(:run)
    # SeedFromAdventure hits OpenAI; stub it out globally so existing
    # bootstrap specs don't need to orchestrate the AI surface. Specific
    # specs below override this to verify the wiring.
    allow(DungeonMaster::Lore::SeedFromAdventure).to receive(:call)
      .and_return(DungeonMaster::Lore::FactsChangeSet.empty)
  end

  subject(:bootstrap) do
    described_class.new(story: story, sheet: sheet, user: user)
  end

  describe "#call" do
    it "creates an Adventure for the user and story" do
      expect { bootstrap.call }.to change { Adventure.count }.by(1)
      adventure = Adventure.last
      expect(adventure.user).to eq(user)
      expect(adventure.story).to eq(story)
    end

    it "returns the persisted, reloaded Adventure" do
      result = bootstrap.call
      expect(result).to be_a(Adventure)
      expect(result).to be_persisted
    end

    it "keeps the world sanity check on by default" do
      adventure = bootstrap.call
      expect(adventure.skip_world_sanity_check).to be(false)
    end

    it "creates an AdventureSheet via SheetCopier" do
      expect { bootstrap.call }.to change { AdventureSheet.count }.by(1)
    end

    it "seeds plot_state with the expected tracking keys" do
      adventure = bootstrap.call
      expect(adventure.plot_state.keys).to include(
        "discovered_clues", "attempted_clues", "reached_milestones",
        "npc_met", "npc_attitudes", "custom_facts"
      )
    end

    it "creates an opening DM message when none exists" do
      expect { bootstrap.call }.to change { AdventureMessage.count }.by(1)
      msg = AdventureMessage.last
      expect(msg.role).to eq("dm")
      expect(msg.message_type).to eq("narrative")
    end

    it "does not create a second opening message if one already exists" do
      adventure = bootstrap.call
      # bootstrap.call always creates a new adventure, so we test the guard
      # directly: calling ensure_opening_message on an adventure that already
      # has a message must be a no-op.
      expect { bootstrap.send(:ensure_opening_message, adventure) }
        .not_to change { AdventureMessage.count }
    end

    context "with directed_dm: true" do
      subject(:bootstrap) do
        described_class.new(story: story, sheet: sheet, user: user, directed_dm: true)
      end

      it "sets directed_dm on the adventure" do
        adventure = bootstrap.call
        expect(adventure.directed_dm).to be(true)
      end
    end

    context "with skip_world_sanity_check: true" do
      subject(:bootstrap) do
        described_class.new(story: story, sheet: sheet, user: user, skip_world_sanity_check: true)
      end

      it "allows callers to skip the world sanity check when requested" do
        adventure = bootstrap.call
        expect(adventure.skip_world_sanity_check).to be(true)
      end
    end

    context "when Embellisher fails" do
      before do
        allow_any_instance_of(DungeonMaster::Embellisher).to receive(:run)
          .and_raise(DungeonMaster::AiError, "timeout")
      end

      it "still creates the adventure and does not re-raise" do
        expect { bootstrap.call }.to change { Adventure.count }.by(1)
      end
    end

    describe "narrative facts seeding (C8)" do
      it "calls Lore::SeedFromAdventure with the new adventure after Embellisher and the opening message" do
        captured = nil
        allow(DungeonMaster::Lore::SeedFromAdventure).to receive(:call) do |adventure:, **_kw|
          captured = {
            adventure: adventure,
            has_opening_message: adventure.adventure_messages.exists?,
          }
          DungeonMaster::Lore::FactsChangeSet.empty
        end

        adventure = bootstrap.call

        expect(DungeonMaster::Lore::SeedFromAdventure).to have_received(:call).once
        expect(captured[:adventure]).to eq(adventure)
        expect(captured[:has_opening_message]).to be(true),
          "expected seeding to run after ensure_opening_message"
      end

      it "does not re-raise when SeedFromAdventure itself raises (belt-and-braces rescue)" do
        allow(DungeonMaster::Lore::SeedFromAdventure).to receive(:call)
          .and_raise(StandardError, "seed service blew up")

        expect { bootstrap.call }.to change { Adventure.count }.by(1)
      end

      context "end-to-end with a stubbed AiClient (ocean premise → state seed fact)" do
        let(:story) { create(:story, premise: "The party is adrift in the middle of the open ocean.") }

        around do |ex|
          original = ActiveJob::Base.queue_adapter
          ActiveJob::Base.queue_adapter = :test
          ex.run
          ActiveJob::Base.queue_adapter = original
        end

        before do
          allow(DungeonMaster::Lore::SeedFromAdventure).to receive(:call).and_call_original

          loremaster_response = {
            "facts" => [
              { "text" => "the party is adrift in the middle of the open ocean",
                "kind" => "state", "entities" => ["party", "ocean"], "polarity" => "asserts" },
            ],
            "invalidates" => [],
            "reasoning" => "seed ocean",
          }

          allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat).and_return(loremaster_response.to_json)
          allow_any_instance_of(DungeonMaster::AiClient).to receive(:parse_json).and_return(loremaster_response)
          allow_any_instance_of(DungeonMaster::AiClient).to receive(:last_parse_status).and_return("success")
          allow_any_instance_of(DungeonMaster::AiClient).to receive(:last_model_used).and_return("gpt-4.1-mini")
          allow_any_instance_of(DungeonMaster::AiClient).to receive(:last_usage).and_return({})
          allow_any_instance_of(DungeonMaster::AiClient).to receive(:embeddings) do |_c, **kw|
            Array(kw[:texts]).map { Array.new(1536) { 0.1 } }
          end
        end

        it "writes a matching `state` seed fact into adventure_narrative_facts" do
          adventure = bootstrap.call

          ocean_fact = AdventureNarrativeFact.where(adventure_id: adventure.id, source: "seed").last
          expect(ocean_fact).to be_present
          expect(ocean_fact.kind).to eq("state")
          expect(ocean_fact.text).to include("ocean")
          expect(ocean_fact.introduced_at_loop_id).to be_nil
        end
      end
    end
  end
end
