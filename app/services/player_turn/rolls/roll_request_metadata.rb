# frozen_string_literal: true

module PlayerTurn
  module Rolls
    module RollRequestMetadata
      class << self
        def build_persist_metadata(result, adventure)
          merged = result[:merged]
          meta = persisted_roll_request_metadata(result, merged, adventure)
          if adventure.combat_active?
            ::Battlefield::EnsureForActiveCombat.call(adventure: adventure)
            adventure.reload
            ref = adventure.combat_context['battlefield_ref']
            if ref.is_a?(Hash)
              meta['battlefield_id'] = ref['id']
              meta['battlefield_version'] = ref['version']
            end
          end
          meta
        end

        # @param metadata [Hash] string-keyed JSON from the roll_request message
        # @return [Array<(Hash, Hash)>] [intent, merged] for finish_resolution
        def resume_inputs(metadata)
          intent = metadata['intent']&.deep_symbolize_keys
          raise Ai::Error, 'Roll-request message metadata missing intent — state integrity failure' unless intent

          merged = {
            player_rolls: [],
            npc_actions: HashArray.symbolize_strict(metadata['pending_npc_actions']),
            consequences: Consequences.normalize(metadata['pending_consequences']),
            mechanical_summaries: metadata['mechanical_summaries'] || [],
            roll_chain: metadata['pending_roll_chain']&.deep_symbolize_keys
          }

          [intent, merged]
        end

        private

        def persisted_roll_request_metadata(result, merged, adventure)
          {
            roll_requests: merged[:player_rolls],
            pending_npc_actions: [],
            pending_consequences: merged[:consequences],
            mechanical_summaries: merged[:mechanical_summaries],
            pending_roll_chain: merged[:roll_chain],
            intent: result[:intent],
            show_dc: adventure.effective_dm_setting('show_roll_dc'),
            remaining_actions: result[:remaining_actions]
          }
        end
      end
    end
  end
end
