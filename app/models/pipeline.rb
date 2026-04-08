# frozen_string_literal: true

# Domain through-line for one player-turn DM run: parent of AdventureLoop rows for that run.
# Separate from PipelineRegistryEntry (operational correlation / timing for logs and admin).
class Pipeline < ApplicationRecord
  belongs_to :adventure
  belongs_to :player_message, class_name: "AdventureMessage", optional: true

  has_many :adventure_loops, dependent: :nullify
end
