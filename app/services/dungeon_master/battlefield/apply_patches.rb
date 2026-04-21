# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # Applies ordered battlefield_patches, bumps row version, syncs combat_context.battlefield_ref.version.
    class ApplyPatches
      class << self
        def call(adventure:, patches:, log: nil)
          return if patches.blank?

          EnsureForActiveCombat.call(adventure: adventure)

          Adventure.transaction do
            adventure.lock!
            adventure.reload

            combat_context = adventure.combat_context
            return unless combat_context.is_a?(Hash)

            battlefield_reference_hash = combat_context["battlefield_ref"] || combat_context[:battlefield_ref]
            return if battlefield_reference_hash.blank?

            battlefield_reference = BattlefieldReference.from_hash(battlefield_reference_hash)
            return unless battlefield_reference

            battlefield_id = battlefield_reference.id
            battlefield = adventure.adventure_battlefields.lock.find_by(id: battlefield_id, status: "active")
            unless battlefield
              log&.log!(:warn, "[Battlefield::ApplyPatches] No active battlefield id=#{battlefield_id}")
              return
            end

            assert_matching_battlefield_version!(battlefield_reference, battlefield)
            patch_state = PatchState.from_battlefield(battlefield)
            mutable_patch_data = patch_state.to_h
            Array(patches).each { |patch_operation| apply_op!(mutable_patch_data, patch_operation) }

            apply_patch_state!(battlefield, patch_state)

            adventure.update!(
              combat_context: CombatContextReferencePatch.attach(combat_context, battlefield: battlefield)
            )
          end
          adventure.reload
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

        def apply_op!(patch_state_data, patch_operation)
          operation_payload = patch_operation.is_a?(Hash) ? patch_operation.deep_stringify_keys : {}
          case operation_payload["op"].to_s
          when "move_token"
            token_id = operation_payload["id"].to_s
            raise ArgumentError, "move_token requires id" if token_id.blank?

            token_payload = (patch_state_data["tokens"][token_id] ||= {})
            token_payload["x"] = operation_payload["x"].to_i if operation_payload.key?("x")
            token_payload["y"] = operation_payload["y"].to_i if operation_payload.key?("y")
          when "shift_viewport"
            viewport_payload = (patch_state_data["viewport"] ||= {})
            if operation_payload["anchor"].is_a?(Hash)
              anchor_payload = operation_payload["anchor"].stringify_keys
              viewport_payload["anchor_x"] = anchor_payload["x"].to_i if anchor_payload.key?("x")
              viewport_payload["anchor_y"] = anchor_payload["y"].to_i if anchor_payload.key?("y")
            end
            viewport_payload["min_x"] = operation_payload["min_x"].to_i if operation_payload.key?("min_x")
            viewport_payload["min_y"] = operation_payload["min_y"].to_i if operation_payload.key?("min_y")
          when "set_cells"
            world_payload = (patch_state_data["world"] ||= {})
            world_cells = (world_payload["cells"] ||= {})
            Array(operation_payload["cells"]).each do |cell_payload|
              raise DungeonMaster::AiError, "set_cells: each cell must be a Hash" unless cell_payload.is_a?(Hash)

              cell_payload = cell_payload.stringify_keys
              unless cell_payload.key?("x") && cell_payload.key?("y")
                raise DungeonMaster::AiError, "set_cells: each cell requires integer x and y"
              end

              cell_attributes = cell_payload.except("x", "y")
              disallowed_attributes = cell_attributes.keys - ALLOWED_CELL_ATTRS
              if disallowed_attributes.any?
                raise DungeonMaster::AiError,
                      "set_cells: disallowed cell attribute(s) #{disallowed_attributes.inspect} — allowed: #{ALLOWED_CELL_ATTRS.join(', ')}"
              end

              cell_key = "#{cell_payload['x']},#{cell_payload['y']}"
              world_cells[cell_key] = cell_attributes.slice(*ALLOWED_CELL_ATTRS)
            end
          else
            raise DungeonMaster::AiError,
                  "battlefield patch: unknown op #{operation_payload['op'].inspect} (supported: move_token, shift_viewport, set_cells)"
          end
        end
      end
    end
  end
end
