require "rails_helper"

RSpec.describe CatalogJsonCache do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:catalog_key) { "catalog_json/feat_definitions" }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    FeatDefinition.create!(id: "power_attack", name: "Power Attack", category: "combat")
  end

  def catalog_names
    JSON.parse(described_class.fetch(FeatDefinition)).pluck("name")
  end

  def catalog_row_selects(&block)
    selects = []
    callback = ->(event) { selects << event.payload[:sql] if event.payload[:sql].include?('SELECT "feat_definitions".*') }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    selects
  end

  it "renders the same JSON as serializing the relation directly" do
    expect(described_class.fetch(FeatDefinition)).to eq(FeatDefinition.all.to_json)
  end

  it "serves repeat reads from the cache without loading the rows again" do
    described_class.fetch(FeatDefinition)

    expect(catalog_row_selects { described_class.fetch(FeatDefinition) }).to be_empty
  end

  describe "invalidation" do
    before { described_class.fetch(FeatDefinition) }

    it "picks up a newly inserted row" do
      FeatDefinition.create!(id: "cleave", name: "Cleave", category: "combat")

      expect(catalog_names).to contain_exactly("Power Attack", "Cleave")
    end

    it "picks up an edited row" do
      travel 1.second
      FeatDefinition.find("power_attack").update!(name: "Power Attack (revised)")

      expect(catalog_names).to eq(["Power Attack (revised)"])
    end

    it "picks up a deleted row" do
      FeatDefinition.find("power_attack").destroy!

      expect(catalog_names).to be_empty
    end
  end

  describe "stampede protection" do
    before do
      described_class.fetch(FeatDefinition)
      FeatDefinition.create!(id: "cleave", name: "Cleave", category: "combat")
    end

    def hold_rebuild_lock
      cache.write("#{catalog_key}/rebuild_lock/#{FeatDefinition.all.cache_version}", true)
    end

    it "lets only the lock winner rebuild once the version moves" do
      winner_selects = catalog_row_selects { described_class.fetch(FeatDefinition) }
      follower_selects = catalog_row_selects { described_class.fetch(FeatDefinition) }

      expect(winner_selects.size).to eq(1)
      expect(follower_selects).to be_empty
    end

    it "serves the previous JSON without touching the rows while another caller rebuilds" do
      hold_rebuild_lock

      selects = catalog_row_selects { expect(catalog_names).to eq(["Power Attack"]) }

      expect(selects).to be_empty
    end

    it "renders inline without writing when the cache is cold and the lock is taken" do
      cache.clear
      hold_rebuild_lock

      expect(catalog_names).to contain_exactly("Power Attack", "Cleave")
      expect(cache.read(catalog_key)).to be_nil
    end
  end
end
