# frozen_string_literal: true

require "rails_helper"

# Smoke spec for commit C1 of the narrative facts plan: asserts the pgvector
# extension is installed in the Dockerized test DB. If this spec fails after
# a fresh checkout it almost always means the postgres image in `compose.yml`
# drifted away from `pgvector/pgvector:pg16` and was replaced with stock
# `postgres:16` — `CREATE EXTENSION vector` cannot run on that image.
RSpec.describe "pgvector extension", type: :db do
  it "is enabled in the current database" do
    row = ActiveRecord::Base.connection.select_one(
      "SELECT extname, extversion FROM pg_extension WHERE extname = 'vector'"
    )
    expect(row).not_to be_nil, "pgvector is not installed in the test DB (check compose.yml postgres image)"
    expect(row["extname"]).to eq("vector")
    expect(row["extversion"]).to match(/\A\d+\.\d+/)
  end
end
