require "rails_helper"

# Tests specifically for the moderation branch in DungeonMasterService#execute_prompt.
# All pipeline steps are stubbed so only the moderation path is exercised.
RSpec.describe DungeonMasterService, type: :service do
  let(:user)        { create(:user) }
  let(:adventure)   { create(:adventure, user: user) }
  let(:service)     { described_class.new(adventure, user: user) }
  let(:player_input) { "I do something questionable." }

  # Stub the player message that prepare_prompt creates in Phase 1.
  let(:player_msg) do
    adventure.adventure_messages.create!(
      role: "player", content: player_input, message_type: "narrative", metadata: {})
  end

  before do
    # Prevent real pipeline from running; only the moderation check is under test.
    allow_any_instance_of(DungeonMaster::PipelineEngine).to receive(:run_prompt)
      .and_return({ action: :narrated, narrative: "stub", adventure_complete: false })

    # Suppress logging side effects.
    allow_any_instance_of(DungeonMaster::Logging).to receive(:start_registry_entry!) { }
    allow_any_instance_of(DungeonMaster::Logging).to receive(:finish_pipeline_segment!) { }
    allow_any_instance_of(DungeonMaster::Logging).to receive(:complete_registry_entry!) { }
    allow_any_instance_of(DungeonMaster::Logging).to receive(:error_registry_entry!) { }
    allow_any_instance_of(DungeonMaster::Logging).to receive(:play_log!) { }
    allow_any_instance_of(DungeonMaster::Logging).to receive(:log!) { }

    # Disable usage limit checks.
    allow(user).to receive(:usage_limit_reached?).and_return(false)
  end

  describe "#execute_prompt" do
    context "with a regular (non-trusted) user" do
      context "when input is flagged" do
        before do
          allow(DungeonMaster::ModerationService).to receive(:call)
            .and_return(DungeonMaster::ModerationService::Result.new(
              flagged: true, response_text: "You recollect yourself."
            ))
        end

        it "returns a moderation_flagged message without running the pipeline" do
          messages = service.execute_prompt(player_input, player_message_id: player_msg.id)
          expect(messages.length).to eq(1)
          expect(messages.first.message_type).to eq("moderation_flagged")
          expect(messages.first.content).to eq("You recollect yourself.")
          expect(messages.first.role).to eq("dm")
        end

        it "does not call the pipeline" do
          service.execute_prompt(player_input, player_message_id: player_msg.id)
          expect_any_instance_of(DungeonMaster::PipelineEngine).not_to receive(:run_prompt)
        end
      end

      context "when input is clean" do
        before do
          allow(DungeonMaster::ModerationService).to receive(:call)
            .and_return(DungeonMaster::ModerationService::Result.new(
              flagged: false, response_text: nil
            ))
        end

        it "proceeds to the pipeline" do
          expect_any_instance_of(DungeonMaster::PipelineEngine).to receive(:run_prompt)
            .and_return({ action: :narrated, narrative: "stub", adventure_complete: false })

          service.execute_prompt(player_input, player_message_id: player_msg.id)
        end
      end
    end

    context "with a trusted user" do
      before { user.update!(trusted: true) }

      it "enqueues ModerationCheckJob instead of blocking" do
        expect(ModerationCheckJob).to receive(:perform_later).with(user.id, player_input)
        service.execute_prompt(player_input, player_message_id: player_msg.id)
      end

      it "does not call ModerationService inline" do
        allow(ModerationCheckJob).to receive(:perform_later)
        expect(DungeonMaster::ModerationService).not_to receive(:call)
        service.execute_prompt(player_input, player_message_id: player_msg.id)
      end

      it "proceeds to the pipeline regardless" do
        allow(ModerationCheckJob).to receive(:perform_later)
        expect_any_instance_of(DungeonMaster::PipelineEngine).to receive(:run_prompt)
          .and_return({ action: :narrated, narrative: "stub", adventure_complete: false })

        service.execute_prompt(player_input, player_message_id: player_msg.id)
      end
    end

    context "when a roll request is pending and the player sends a fresh prompt" do
      let(:player_input) { "Actually, I'll do something else." }

      before do
        allow(DungeonMaster::ModerationService).to receive(:call)
          .and_return(DungeonMaster::ModerationService::Result.new(
            flagged: false, response_text: nil
          ))

        adventure.adventure_messages.create!(
          role: "dm",
          content: "Roll for Stealth.",
          message_type: "roll_request",
          metadata: {
            "intent" => { "intention" => "I sneak up to the goblins" },
            "roll_requests" => [{ "type" => "skill_check", "skill" => "Stealth", "dc" => 15 }]
          }
        )
      end

      it "starts a fresh prompt pipeline instead of resuming the pending roll" do
        expect_any_instance_of(DungeonMaster::PipelineEngine).to receive(:run_prompt)
          .with(player_input, prompt_mode: nil)
          .and_return({ action: :narrated, narrative: "stub", adventure_complete: false })

        service.execute_prompt(player_input, player_message_id: player_msg.id)
      end
    end
  end
end
