# frozen_string_literal: true

# Enables the pgvector extension, which backs the embedding column on
# `adventure_narrative_facts`. The Dockerized postgres service uses the
# pgvector/pgvector:pg16 image so the shared object is already present on
# disk; this migration just exposes it at the database level.
#
# Split from the table-creation migration so the extension is reviewable and
# revertable on its own (commit C1 of the narrative facts plan).
class EnablePgvectorExtension < ActiveRecord::Migration[7.1]
  def change
    enable_extension "vector"
  end
end
