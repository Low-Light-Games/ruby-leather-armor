require "rails_helper"

RSpec.describe StripeWebhookEvent, type: :model do
  describe "validations" do
    subject(:event) do
      described_class.new(
        stripe_event_id: "evt_123",
        event_type: "checkout.session.completed",
        processed_at: Time.current,
        payload_digest: "abc123"
      )
    end

    it { should validate_presence_of(:stripe_event_id) }
    it { should validate_uniqueness_of(:stripe_event_id) }
    it { should validate_presence_of(:event_type) }
    it { should validate_presence_of(:processed_at) }
    it { should validate_presence_of(:payload_digest) }
  end
end
