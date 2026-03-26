# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenaiModelCatalog, type: :service do
  describe ".normalize" do
    # Versioned aliases returned by the OpenAI API response body
    it "strips a YYYY-MM-DD date suffix" do
      expect(described_class.normalize("gpt-4o-mini-2024-07-18")).to eq("gpt-4o-mini")
    end

    it "strips a date suffix from a full model name" do
      expect(described_class.normalize("gpt-4o-2024-08-06")).to eq("gpt-4o")
    end

    it "strips a date suffix that includes a -preview tag" do
      expect(described_class.normalize("gpt-4o-mini-2024-07-18-preview")).to eq("gpt-4o-mini")
    end

    it "strips a date suffix from an o-series model" do
      expect(described_class.normalize("o1-mini-2024-09-12")).to eq("o1-mini")
    end

    # Base aliases — must pass through unchanged
    it "does not alter a plain model alias with no date" do
      expect(described_class.normalize("gpt-4o-mini")).to eq("gpt-4o-mini")
    end

    it "does not alter a model name whose numeric segment is not a date" do
      expect(described_class.normalize("gpt-4-turbo")).to eq("gpt-4-turbo")
    end

    it "does not alter a model name with a version number rather than a date" do
      expect(described_class.normalize("gpt-4.1-mini")).to eq("gpt-4.1-mini")
    end

    it "does not alter an o-series base alias" do
      expect(described_class.normalize("o3-mini")).to eq("o3-mini")
    end

    it "does not strip a partial date-like suffix that is not YYYY-MM-DD" do
      expect(described_class.normalize("gpt-4o-mini-2024-07")).to eq("gpt-4o-mini-2024-07")
    end

    it "does not strip digits that appear mid-name rather than as a trailing date" do
      expect(described_class.normalize("gpt-4o")).to eq("gpt-4o")
    end

    it "handles nil-safe input by converting to string" do
      expect(described_class.normalize(nil)).to eq("")
    end
  end
end
