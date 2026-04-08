# frozen_string_literal: true

module DungeonMaster
  module Rolls
    # Shape of `adventure_messages.metadata` when message_type is "roll_request"
    # (persisted from DungeonMasterService#messages_for on :awaiting_rolls).
    #
    # When the player submits roll results, the pipeline reloads that JSON and must
    # rebuild the same `intent` + `merged` hash that AdventureLoopResolution#finish_resolution
    # had in memory before the pause. Player roll rows are not rehydrated from
    # metadata — they arrive as `roll_results` and are merged via Rolls::PlayerRolls.
    module RollRequestMetadata
      class << self
        # @param metadata [Hash] string-keyed JSON from the roll_request message
        # @return [Array<(Hash, Hash)>] [intent, merged] for finish_resolution
        def resume_inputs(metadata)
          intent = metadata["intent"]&.deep_symbolize_keys
          unless intent
            raise AiError, "Roll-request message metadata missing intent — state integrity failure"
          end

          merged = {
            player_rolls: [],
            npc_actions: deep_symbolize_array(metadata["pending_npc_actions"]),
            consequences: deep_symbolize_array(metadata["pending_consequences"]),
            mechanical_summaries: metadata["mechanical_summaries"] || []
          }

          [intent, merged]
        end

        private

        def deep_symbolize_array(value)
          Array(value).map(&:deep_symbolize_keys)
        end
      end
    end
  end
end
