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

            ctx = adventure.combat_context
            return unless ctx.is_a?(Hash)

            ref = ctx["battlefield_ref"] || ctx[:battlefield_ref]
            return if ref.blank?
            battlefield_reference = BattlefieldReference.from_hash(ref)
            return unless battlefield_reference

            bf_id = battlefield_reference.id
            bf = adventure.adventure_battlefields.lock.find_by(id: bf_id, status: "active")
            unless bf
              log&.log!(:warn, "[Battlefield::ApplyPatches] No active battlefield id=#{bf_id}")
              return
            end

            expected = battlefield_reference.version
            if expected.present? && expected.to_i != bf.version.to_i
              raise DungeonMaster::AiError,
                    "battlefield version drift: combat_context has #{expected}, row has #{bf.version}"
            end

            data = {
              "tokens" => bf.tokens.deep_dup,
              "viewport" => bf.viewport.deep_dup,
              "world" => bf.world.deep_dup
            }
            Array(patches).each { |op| apply_op!(data, op) }

            bf.assign_attributes(
              tokens: data["tokens"],
              viewport: data["viewport"],
              world: data["world"],
              version: bf.version.to_i + 1
            )
            bf.save!

            adventure.update!(
              combat_context: CombatContextReferencePatch.attach(ctx, battlefield: bf)
            )
          end
          adventure.reload
        end

        # Only these keys may appear on a cell payload (besides x/y). Everything else is rejected
        # so model typos cannot desync narrative from persisted battlefield state.
        ALLOWED_CELL_ATTRS = %w[terrain difficult cover light obstacle note labels].freeze

        private

        def apply_op!(data, op)
          h = op.is_a?(Hash) ? op.deep_stringify_keys : {}
          case h["op"].to_s
          when "move_token"
            id = h["id"].to_s
            raise ArgumentError, "move_token requires id" if id.blank?
            tok = (data["tokens"][id] ||= {})
            tok["x"] = h["x"].to_i if h.key?("x")
            tok["y"] = h["y"].to_i if h.key?("y")
          when "shift_viewport"
            vp = (data["viewport"] ||= {})
            if h["anchor"].is_a?(Hash)
              a = h["anchor"].stringify_keys
              vp["anchor_x"] = a["x"].to_i if a.key?("x")
              vp["anchor_y"] = a["y"].to_i if a.key?("y")
            end
            vp["min_x"] = h["min_x"].to_i if h.key?("min_x")
            vp["min_y"] = h["min_y"].to_i if h.key?("min_y")
          when "set_cells"
            world = (data["world"] ||= {})
            cells = (world["cells"] ||= {})
            Array(h["cells"]).each do |c|
              raise DungeonMaster::AiError, "set_cells: each cell must be a Hash" unless c.is_a?(Hash)

              c = c.stringify_keys
              unless c.key?("x") && c.key?("y")
                raise DungeonMaster::AiError, "set_cells: each cell requires integer x and y"
              end

              payload = c.except("x", "y")
              bad = payload.keys - ALLOWED_CELL_ATTRS
              if bad.any?
                raise DungeonMaster::AiError,
                      "set_cells: disallowed cell attribute(s) #{bad.inspect} — allowed: #{ALLOWED_CELL_ATTRS.join(', ')}"
              end

              key = "#{c['x']},#{c['y']}"
              cells[key] = payload.slice(*ALLOWED_CELL_ATTRS)
            end
          else
            raise DungeonMaster::AiError,
                  "battlefield patch: unknown op #{h['op'].inspect} (supported: move_token, shift_viewport, set_cells)"
          end
        end
      end
    end
  end
end
