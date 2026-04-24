require "rails_helper"

RSpec.describe "AI usage limit enforcement", type: :service do
  include_context "with mocked ai"

  let(:user)      { create(:user) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure).tap(&:recompute_derived_stats!) }

  describe "User#usage_limit_reached?" do
    it "returns false for a fresh user" do
      expect(user.usage_limit_reached?).to be false
    end

    it "returns true when monthly usage meets the free plan token limit" do
      limit = StripePlans.token_limit_for("free")
      user.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: limit / 2, output_tokens: limit / 2, reasoning_tokens: 0, total_tokens: limit,
        input_cost_microdollars: 100,
        output_cost_microdollars: 100,
        total_cost_microdollars: 200
      )

      expect(user.usage_limit_reached?).to be true
    end

    it "returns false when usage is below the limit" do
      limit = StripePlans.token_limit_for("free")
      user.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: 10, output_tokens: 5, reasoning_tokens: 0, total_tokens: 15,
        input_cost_microdollars: 100,
        output_cost_microdollars: 100,
        total_cost_microdollars: 200
      )

      expect(user.usage_limit_reached?).to be false
    end

    it "only counts records from the current month" do
      limit = StripePlans.token_limit_for("free")
      user.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: limit / 2, output_tokens: limit / 2, reasoning_tokens: 0, total_tokens: limit,
        input_cost_microdollars: 100,
        output_cost_microdollars: 100,
        total_cost_microdollars: 200,
        created_at: 2.months.ago
      )

      expect(user.usage_limit_reached?).to be false
    end

    it "respects the higher paid plan limits" do
      create(:user_stripe_profile, user: user, plan_key: "scout")
      free_limit = StripePlans.token_limit_for("free")

      user.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: free_limit / 2, output_tokens: free_limit / 2, reasoning_tokens: 0, total_tokens: free_limit,
        input_cost_microdollars: 100,
        output_cost_microdollars: 100,
        total_cost_microdollars: 200
      )

      expect(user.usage_limit_reached?).to be false
    end

    it "does not enforce plan limits for admins" do
      admin = create(:user, :admin)
      limit = StripePlans.token_limit_for("free")
      admin.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: limit, output_tokens: 0, reasoning_tokens: 0, total_tokens: limit,
        input_cost_microdollars: 100,
        output_cost_microdollars: 100,
        total_cost_microdollars: 200
      )

      expect(admin.usage_limit_reached?).to be false
    end
  end

  describe "User#usage_percentage" do
    it "returns 0.0 for a fresh user" do
      expect(user.usage_percentage).to eq(0.0)
    end

    it "returns 100.0 when at limit" do
      limit = StripePlans.token_limit_for("free")
      user.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: limit, output_tokens: 0, reasoning_tokens: 0, total_tokens: limit,
        input_cost_microdollars: 100,
        output_cost_microdollars: 0,
        total_cost_microdollars: 100
      )

      expect(user.usage_percentage).to eq(100.0)
    end

    it "caps at 100.0 when over limit" do
      limit = StripePlans.token_limit_for("free")
      user.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: limit * 2, output_tokens: 0, reasoning_tokens: 0, total_tokens: limit * 2,
        input_cost_microdollars: 100,
        output_cost_microdollars: 0,
        total_cost_microdollars: 100
      )

      expect(user.usage_percentage).to eq(100.0)
    end
  end

  describe "AdventurePolicy#pipeline?" do
    let(:policy) { AdventurePolicy.new(user, adventure) }

    it "is true when the user may view the adventure and is under the usage limit" do
      expect(policy.pipeline?).to be true
    end

    it "is false when the user has hit the usage limit" do
      limit = StripePlans.token_limit_for("free")
      user.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: limit, output_tokens: 0, reasoning_tokens: 0, total_tokens: limit,
        input_cost_microdollars: 100,
        output_cost_microdollars: 0,
        total_cost_microdollars: 100
      )

      expect(policy.pipeline?).to be false
    end

    it "is false when the user does not own the adventure (and is not admin)" do
      other = create(:user)
      expect(AdventurePolicy.new(other, adventure).pipeline?).to be false
    end

    it "raises UsageLimitExceeded from DungeonMasterService when pipeline? is false" do
      limit = StripePlans.token_limit_for("free")
      user.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: limit, output_tokens: 0, reasoning_tokens: 0, total_tokens: limit,
        input_cost_microdollars: 100,
        output_cost_microdollars: 0,
        total_cost_microdollars: 100
      )

      service = DungeonMasterService.new(adventure, user: user)
      expect { service.send(:enforce_pipeline_policy!) }.to raise_error(DungeonMaster::UsageLimitExceeded)
    end

    it "includes a player-friendly message on UsageLimitExceeded from enforce_pipeline_policy!" do
      limit = StripePlans.token_limit_for("free")
      user.ai_usage_records.create!(
        model_id: "gpt-4o-mini",
        input_tokens: limit, output_tokens: 0, reasoning_tokens: 0, total_tokens: limit,
        input_cost_microdollars: 100,
        output_cost_microdollars: 0,
        total_cost_microdollars: 100
      )

      service = DungeonMasterService.new(adventure, user: user)
      begin
        service.send(:enforce_pipeline_policy!)
        fail "Expected UsageLimitExceeded"
      rescue DungeonMaster::UsageLimitExceeded => e
        expect(e.message).to include("monthly usage limit")
      end
    end
  end
end
