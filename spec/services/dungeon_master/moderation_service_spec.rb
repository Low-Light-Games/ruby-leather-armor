# frozen_string_literal: true

require "rails_helper"

RSpec.describe DungeonMaster::ModerationService, type: :service do
  let(:user)  { create(:user) }
  let(:input) { "I want to attack the goblin." }

  def stub_moderation(flagged:, categories: {})
    category_scores = DungeonMaster::ModerationService::CONFIG
                        .fetch("response_text", "") # just to load config without error
    allow_any_instance_of(OpenAI::Client).to receive(:moderations).and_return(
      "results" => [
        {
          "flagged"    => flagged,
          "categories" => categories
        }
      ]
    )
  end

  describe ".call" do
    context "when input is not flagged" do
      before { stub_moderation(flagged: false) }

      it "returns a non-flagged result" do
        result = described_class.call(input, user: user)
        expect(result.flagged?).to be false
      end

      it "does not create a ModerationEvent" do
        expect { described_class.call(input, user: user) }
          .not_to change(ModerationEvent, :count)
      end

      it "does not increment user strikes" do
        expect { described_class.call(input, user: user) }
          .not_to change { user.reload.moderation_strikes }
      end
    end

    context "when input is flagged" do
      let(:categories) { { "violence" => true, "hate" => false } }

      before { stub_moderation(flagged: true, categories: categories) }

      it "returns a flagged result" do
        result = described_class.call(input, user: user)
        expect(result.flagged?).to be true
      end

      it "returns the configured response text" do
        result = described_class.call(input, user: user)
        expect(result.response_text).to eq(DungeonMaster::ModerationService::CONFIG["response_text"])
      end

      it "creates a ModerationEvent" do
        expect { described_class.call(input, user: user) }
          .to change(ModerationEvent, :count).by(1)
      end

      it "records the strike number on the event" do
        described_class.call(input, user: user)
        expect(ModerationEvent.last.strike_number).to eq(1)
      end

      it "stores the input excerpt" do
        described_class.call(input, user: user)
        expect(ModerationEvent.last.input_excerpt).to eq(input)
      end

      it "stores only flagged categories" do
        described_class.call(input, user: user)
        expect(ModerationEvent.last.flagged_categories).to include("violence" => true)
      end

      it "increments user moderation_strikes" do
        expect { described_class.call(input, user: user) }
          .to change { user.reload.moderation_strikes }.by(1)
      end

      context "when strikes reach the ban threshold" do
        before do
          threshold = DungeonMaster::ModerationService::CONFIG["strikes_before_ban"]
          user.update!(moderation_strikes: threshold - 1)
        end

        it "bans the user" do
          described_class.call(input, user: user)
          expect(user.reload.banned?).to be true
        end

        it "sets banned_at" do
          described_class.call(input, user: user)
          expect(user.reload.banned_at).to be_present
        end

        it "marks the event as auto_banned" do
          described_class.call(input, user: user)
          expect(ModerationEvent.last.auto_banned).to be true
        end
      end

      context "when the user is trusted and hits the untrust threshold" do
        before do
          threshold = DungeonMaster::ModerationService::CONFIG["strikes_before_untrust"]
          user.update!(trusted: true, moderation_strikes: threshold - 1)
        end

        it "revokes trust" do
          described_class.call(input, user: user)
          expect(user.reload.trusted?).to be false
        end

        it "marks the event as auto_untrusted" do
          described_class.call(input, user: user)
          expect(ModerationEvent.last.auto_untrusted).to be true
        end
      end
    end

    context "when the OpenAI API raises a network error" do
      before do
        allow_any_instance_of(OpenAI::Client).to receive(:moderations)
          .and_raise(Faraday::ConnectionFailed.new("timeout"))
      end

      it "returns a non-flagged result (fail open)" do
        result = described_class.call(input, user: user)
        expect(result.flagged?).to be false
      end

      it "does not create a ModerationEvent" do
        expect { described_class.call(input, user: user) }
          .not_to change(ModerationEvent, :count)
      end
    end

    context "when user is nil" do
      before { stub_moderation(flagged: true, categories: { "violence" => true }) }

      it "does not raise" do
        expect { described_class.call(input, user: nil) }.not_to raise_error
      end

      it "does not create a ModerationEvent" do
        expect { described_class.call(input, user: nil) }
          .not_to change(ModerationEvent, :count)
      end
    end
  end
end
