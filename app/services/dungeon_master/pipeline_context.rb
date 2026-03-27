# frozen_string_literal: true

module DungeonMaster
  # Immutable value object carrying pipeline-level data assembled after all
  # action loops resolve, before the narrative phase runs.
  #
  # Distinct from AdventureLoop (@loop), which holds data for a single
  # sequenced action. PipelineContext spans the whole turn — for single-action
  # turns the two overlap; for multi-action turns only this object has the
  # full picture.
  PipelineContext = Struct.new(:combined_seed, :dm_brief, :player_action, :prior_outcomes, keyword_init: true)
end
