# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # Applies ordered battlefield_patches, bumps row version, syncs combat_context.battlefield_ref.version.
    class ApplyPatches
      class << self
        def call(adventure:, patches:, log: nil)
          return if patches.blank?

          EnsureForActiveCombat.call(adventure: adventure)
          adventure.reload

          ctx = adventure.combat_context
          return unless ctx.is_a?(Hash)

          ref = ctx["battlefield_ref"] || ctx[:battlefield_ref]
          return if ref.blank?

          bf_id = ref["id"] || ref[:id]
          Adventure.transaction do
            bf = adventure.adventure_battlefields.lock.find_by(id: bf_id, status: "active")
            unless bf
              log&.log!(:warn, "[Battlefield::ApplyPatches] No active battlefield id=#{bf_id}")
              next
            end

            expected = ref["version"] || ref[:version]
            if expected.present? && expected.to_i != bf.version.to_i
              if Rails.env.development? || Rails.env.test?
                raise DungeonMaster::AiError, "battlefield version drift: combat_context has #{expected}, row has #{bf.version}"
              end
              log&.log!(:warn, "[Battlefield::ApplyPatches] version drift before apply ctx=#{expected} row=#{bf.version}")
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

            new_ctx = ctx.deep_stringify_keys
            new_ref = (new_ctx["battlefield_ref"] || {}).merge(
              "id" => bf.id,
              "version" => bf.version,
              "topology" => bf.topology
            )
            new_ctx["battlefield_ref"] = new_ref
            adventure.update!(combat_context: new_ctx)
          end
          adventure.reload
        end

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
              next unless c.is_a?(Hash)
              c = c.stringify_keys
              key = "#{c['x']},#{c['y']}"
              cells[key] = c.except("x", "y")
            end
          else
            Rails.logger.info("[Battlefield::ApplyPatches] unknown op #{h['op'].inspect} — skipped")
          end
        end
      end
    end
  end
end
