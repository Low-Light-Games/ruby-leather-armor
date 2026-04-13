require "rails_helper"
require "webmock/rspec"

RSpec.describe DungeonMaster::ModerationService, type: :service do
  let(:user) { create(:user) }
  let(:player_input) { "I attack the guard viciously." }
  let(:evaluator_base) { ENV.fetch("EVALUATOR_URL", "http://evaluator:3001") }
  let(:moderate_url) { "#{evaluator_base}/moderate" }

  def stub_moderate(flagged:, categories: {})
    WebMock.stub_request(:post, moderate_url)
           .to_return(
             status: 200,
             body: { "flagged" => flagged, "categories" => categories,
                     "category_scores" => {} }.to_json,
             headers: { "Content-Type" => "application/json" }
           )
  end

  before { WebMock.enable! }
  after  { WebMock.reset!; WebMock.disable! }

  describe ".call" do
    context "when moderation is disabled" do
      before { allow(ModerationConfig.instance).to receive(:enabled?).and_return(false) }

      it "returns a non-flagged result without calling the evaluator" do
        result = described_class.call(player_input, user: user)
        expect(result.flagged?).to be false
        expect(a_request(:post, moderate_url)).not_to have_been_made
      end
    end

    context "when the evaluator returns clean" do
      before do
        allow(ModerationConfig.instance).to receive(:enabled?).and_return(true)
        stub_moderate(flagged: false)
      end

      it "returns a non-flagged result" do
        result = described_class.call(player_input, user: user)
        expect(result.flagged?).to be false
        expect(result.response_text).to be_nil
      end

      it "does not increment strikes" do
        expect { described_class.call(player_input, user: user) }
          .not_to change { user.reload.moderation_strikes }
      end

      it "does not create a ModerationEvent" do
        expect { described_class.call(player_input, user: user) }
          .not_to change(ModerationEvent, :count)
      end
    end

    context "when the evaluator flags the input" do
      let(:categories) { { "violence" => true, "harassment" => false } }

      before do
        allow(ModerationConfig.instance).to receive(:enabled?).and_return(true)
        allow(ModerationConfig.instance).to receive(:max_strikes).and_return(3)
        allow(ModerationConfig.instance).to receive(:default_response).and_return("You recollect yourself.")
        allow(ModerationConfig.instance).to receive(:ignored_categories).and_return([])
        stub_moderate(flagged: true, categories: categories)
      end

      it "returns a flagged result with the configured default_response" do
        result = described_class.call(player_input, user: user)
        expect(result.flagged?).to be true
        expect(result.response_text).to eq("You recollect yourself.")
      end

      it "increments the user's moderation_strikes" do
        expect { described_class.call(player_input, user: user) }
          .to change { user.reload.moderation_strikes }.by(1)
      end

      it "creates a ModerationEvent with correct attributes" do
        expect { described_class.call(player_input, user: user) }
          .to change(ModerationEvent, :count).by(1)

        event = ModerationEvent.last
        expect(event.user).to eq(user)
        expect(event.strike_number).to eq(1)
        expect(event.flagged_categories).to include("violence" => true)
        expect(event.auto_banned).to be false
        expect(event.auto_untrusted).to be false
        expect(event.input_excerpt).to include("attack")
      end

      context "when the strike hits the max_strikes threshold" do
        before do
          allow(ModerationConfig.instance).to receive(:max_strikes).and_return(1)
        end

        it "bans the user" do
          described_class.call(player_input, user: user)
          expect(user.reload.banned?).to be true
          expect(user.reload.banned_at).to be_present
        end

        it "records auto_banned: true on the event" do
          described_class.call(player_input, user: user)
          expect(ModerationEvent.last.auto_banned).to be true
        end
      end

      context "when the user is trusted and hits max_strikes" do
        before do
          user.update!(trusted: true)
          allow(ModerationConfig.instance).to receive(:max_strikes).and_return(1)
        end

        it "revokes trust alongside the ban" do
          described_class.call(player_input, user: user)
          expect(user.reload.trusted?).to be false
          expect(user.reload.banned?).to be true
        end

        it "records auto_untrusted: true on the event" do
          described_class.call(player_input, user: user)
          expect(ModerationEvent.last.auto_untrusted).to be true
        end
      end

      context "when the user is trusted but below max_strikes" do
        before do
          user.update!(trusted: true)
          allow(ModerationConfig.instance).to receive(:max_strikes).and_return(5)
        end

        it "does not revoke trust" do
          described_class.call(player_input, user: user)
          expect(user.reload.trusted?).to be true
        end

        it "does not ban the user" do
          described_class.call(player_input, user: user)
          expect(user.reload.banned?).to be false
        end
      end
    end

    context "when the evaluator is unreachable" do
      before do
        allow(ModerationConfig.instance).to receive(:enabled?).and_return(true)
        WebMock.stub_request(:post, moderate_url).to_raise(Errno::ECONNREFUSED)
      end

      it "raises AiError" do
        expect { described_class.call(player_input, user: user) }
          .to raise_error(DungeonMaster::AiError, /unreachable/)
      end
    end

    context "when the evaluator returns an HTTP error" do
      before do
        allow(ModerationConfig.instance).to receive(:enabled?).and_return(true)
        WebMock.stub_request(:post, moderate_url)
               .to_return(status: 500, body: { "error" => "Internal error" }.to_json,
                          headers: { "Content-Type" => "application/json" })
      end

      it "raises AiError" do
        expect { described_class.call(player_input, user: user) }
          .to raise_error(DungeonMaster::AiError, /Moderation evaluator failed/)
      end
    end
  end
end
