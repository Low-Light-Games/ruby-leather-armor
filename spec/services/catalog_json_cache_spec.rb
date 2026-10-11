require "rails_helper"

RSpec.describe CatalogJsonCache do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    FeatDefinition.create!(id: "power_attack", name: "Power Attack", category: "combat")
    described_class.fetch(FeatDefinition)
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

  def hold_rebuild_lock
    cache.write("catalog_json/feat_definitions/rebuild_lock/#{FeatDefinition.all.cache_version}", true)
  end

  it "serves a hit without loading the rows" do
    expect(catalog_row_selects { described_class.fetch(FeatDefinition) }).to be_empty
  end

  it "picks up a write to the catalog" do
    FeatDefinition.create!(id: "cleave", name: "Cleave", category: "combat")

    expect(catalog_names).to contain_exactly("Power Attack", "Cleave")
  end

  context "when the catalog changes" do
    before { FeatDefinition.create!(id: "cleave", name: "Cleave", category: "combat") }

    it "lets only the lock winner rebuild" do
      winner_selects = catalog_row_selects { described_class.fetch(FeatDefinition) }
      follower_selects = catalog_row_selects { described_class.fetch(FeatDefinition) }

      expect(winner_selects.size).to eq(1)
      expect(follower_selects).to be_empty
    end

    it "serves the previous JSON while someone else rebuilds" do
      hold_rebuild_lock

      expect(catalog_names).to eq(["Power Attack"])
    end

    it "renders without caching when cold and someone else rebuilds" do
      cache.clear
      hold_rebuild_lock

      expect(catalog_names).to contain_exactly("Power Attack", "Cleave")
      expect(cache.read("catalog_json/feat_definitions")).to be_nil
    end
  end
end
