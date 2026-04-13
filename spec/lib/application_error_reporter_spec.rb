# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationErrorReporter do
  describe ".notify" do
    it "reports to Rails.error with handled: true" do
      ex = StandardError.new("boom")
      expect(Rails.error).to receive(:report).with(
        ex,
        hash_including(handled: true, context: hash_including("foo" => "bar"))
      )
      described_class.notify(ex, context: { foo: "bar" })
    end
  end
end
