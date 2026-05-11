# frozen_string_literal: true

module PlayerTurn
  module ProgressiveNarrativeMetadata
    module_function

    def for_entry(narrative_entry)
      {
        sequence_index: narrative_entry[:sequence_index],
        total_actions:  narrative_entry[:total_actions],
        action_text:    narrative_entry[:action_text]
      }
    end
  end
end
