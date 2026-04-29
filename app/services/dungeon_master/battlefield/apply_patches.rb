# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # Applies ordered battlefield_patches, bumps row version, syncs combat_context.battlefield_ref.version.
    class ApplyPatches
      class << self
        def call(adventure:, patches:, log: nil)
          return if patches.blank?

          EnsureForActiveCombat.call(adventure: adventure)
          Adventure.transaction { apply_within_locked_adventure!(adventure, patches, log) }
          adventure.reload
        end

        def apply_within_locked_adventure!(adventure, patches, log)
          adventure.lock!
          adventure.reload
          combat_context = adventure.combat_context
          return unless combat_context.is_a?(Hash)

          battlefield_reference = lookup_battlefield_reference(combat_context)
          return unless battlefield_reference

          battlefield = lookup_active_battlefield(adventure, battlefield_reference, log)
          return unless battlefield

          apply_and_persist_patches!(adventure, combat_context, battlefield, battlefield_reference, patches)
        end

        def lookup_battlefield_reference(combat_context)
          ref_hash = combat_context['battlefield_ref'] || combat_context[:battlefield_ref]
          return nil if ref_hash.blank?

          BattlefieldReference.from_hash(ref_hash)
        end

        def lookup_active_battlefield(adventure, battlefield_reference, log)
          battlefield = adventure.adventure_battlefields.lock.find_by(id: battlefield_reference.id, status: 'active')
          return battlefield if battlefield

          log&.log!(:warn, "[Battlefield::ApplyPatches] No active battlefield id=#{battlefield_reference.id}")
          nil
        end

        def apply_and_persist_patches!(adventure, combat_context, battlefield, battlefield_reference, patches)
          assert_matching_battlefield_version!(battlefield_reference, battlefield)
          patch_state = PatchState.from_battlefield(battlefield)
          mutable_patch_data = patch_state.to_h
          Array(patches).each { |patch_operation| apply_op!(mutable_patch_data, patch_operation) }

          apply_patch_state!(battlefield, patch_state)
          adventure.update!(
            combat_context: CombatContextReferencePatch.attach(combat_context, battlefield: battlefield)
          )
        end

        # Only these keys may appear on a cell payload (besides x/y). Everything else is rejected
        # so model typos cannot desync narrative from persisted battlefield state.
        ALLOWED_CELL_ATTRS = %w[terrain difficult cover light obstacle note labels].freeze

        private

        def assert_matching_battlefield_version!(battlefield_reference, battlefield)
          expected_version = battlefield_reference.version
          return if expected_version.blank?

          return if expected_version.to_i == battlefield.version.to_i

          raise DungeonMaster::AiError,
                "battlefield version drift: combat_context has #{expected_version}, row has #{battlefield.version}"
        end

        def apply_patch_state!(battlefield, patch_state)
          battlefield.assign_attributes(
            tokens: patch_state.tokens,
            viewport: patch_state.viewport,
            world: patch_state.world,
            version: battlefield.version.to_i + 1
          )
          battlefield.save!
        end

        # Accepts the canonical Combat GM shape (op/id/x/y) and the
        # alternate verbose shape some prompt variants emit
        # (operation/token_id/to_x/to_y). Forgiving the names avoids
        # crashing combat when the AI free-writes a synonym from the
        # prompt's natural-language hint.
        def apply_op!(patch_state_data, patch_operation)
          operation = patch_operation.is_a?(Hash) ? patch_operation.deep_stringify_keys : {}
          name = (operation['op'] || operation['operation']).to_s
          case name
          when 'move_token' then apply_move_token!(patch_state_data, operation)
          when 'shift_viewport' then apply_shift_viewport!(patch_state_data, operation)
          when 'set_cells' then apply_set_cells!(patch_state_data, operation)
          else
            raise DungeonMaster::AiError,
                  "battlefield patch: unknown op #{name.inspect} (supported: move_token, shift_viewport, set_cells)"
          end
        end

        def apply_move_token!(patch_state_data, operation)
          token_id = (operation['id'] || operation['token_id']).to_s
          raise ArgumentError, 'move_token requires id' if token_id.blank?

          token_payload = (patch_state_data['tokens'][token_id] ||= {})
          assign_token_coordinates!(token_payload, operation)
        end

        def assign_token_coordinates!(token_payload, operation)
          new_x = operation['x'] || operation['to_x']
          new_y = operation['y'] || operation['to_y']
          token_payload['x'] = new_x.to_i unless new_x.nil?
          token_payload['y'] = new_y.to_i unless new_y.nil?
        end

        def apply_shift_viewport!(patch_state_data, operation)
          viewport_payload = (patch_state_data['viewport'] ||= {})
          apply_viewport_anchor!(viewport_payload, operation['anchor'])
          viewport_payload['min_x'] = operation['min_x'].to_i if operation.key?('min_x')
          viewport_payload['min_y'] = operation['min_y'].to_i if operation.key?('min_y')
        end

        def apply_viewport_anchor!(viewport_payload, anchor)
          return unless anchor.is_a?(Hash)

          anchor_payload = anchor.stringify_keys
          viewport_payload['anchor_x'] = anchor_payload['x'].to_i if anchor_payload.key?('x')
          viewport_payload['anchor_y'] = anchor_payload['y'].to_i if anchor_payload.key?('y')
        end

        def apply_set_cells!(patch_state_data, operation)
          world_payload = (patch_state_data['world'] ||= {})
          world_cells = (world_payload['cells'] ||= {})
          Array(operation['cells']).each { |cell_payload| apply_set_cell!(world_cells, cell_payload) }
        end

        def apply_set_cell!(world_cells, cell_payload)
          raise DungeonMaster::AiError, 'set_cells: each cell must be a Hash' unless cell_payload.is_a?(Hash)

          cell_payload = cell_payload.stringify_keys
          unless cell_payload.key?('x') && cell_payload.key?('y')
            raise DungeonMaster::AiError, 'set_cells: each cell requires integer x and y'
          end

          attrs = cell_payload.except('x', 'y')
          disallowed = attrs.keys - ALLOWED_CELL_ATTRS
          if disallowed.any?
            raise DungeonMaster::AiError,
                  "set_cells: disallowed cell attribute(s) #{disallowed.inspect} " \
                  "— allowed: #{ALLOWED_CELL_ATTRS.join(', ')}"
          end

          world_cells["#{cell_payload['x']},#{cell_payload['y']}"] = attrs.slice(*ALLOWED_CELL_ATTRS)
        end
      end
    end
  end
end
