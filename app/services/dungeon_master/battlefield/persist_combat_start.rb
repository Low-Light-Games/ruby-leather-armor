# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # Atomic combat start: Warmaster combat hash + adventure_battlefields row + battlefield_ref
    # + action_economy in one transaction.
    class PersistCombatStart
      class << self
        def call(adventure:, combat_data:, sheet:)
          data = combat_data.deep_stringify_keys
          raise ArgumentError, "combat_data must be a Hash" unless data.is_a?(Hash)

          Adventure.transaction do
            adventure.lock!

            desired_tokens = build_tokens_from_participants(data["participants"])
            actives = adventure.adventure_battlefields.where(status: "active").order(:id).to_a
            matching = actives.find { |bf| token_sets_match?(bf.tokens, desired_tokens) }

            ref = if matching
                    (actives - [matching]).each(&:archive!)
                    {
                      "id" => matching.id,
                      "version" => matching.version,
                      "topology" => matching.topology
                    }
                  else
                    actives.each(&:archive!)
                    bf = adventure.adventure_battlefields.create!(
                      status: "active",
                      topology: "square",
                      world: default_world,
                      tokens: desired_tokens,
                      viewport: viewport_for_tokens(desired_tokens),
                      version: 1
                    )
                    { "id" => bf.id, "version" => bf.version, "topology" => bf.topology }
                  end

            data["battlefield_ref"] = ref
            holder = data["current_turn"].presence || DungeonMaster::Utilities::CombatTurnCalculator::PLAYER_NAME
            data["action_economy"] ||= ActionEconomy.build_for_turn_holder(
              holder, combat_ctx: data, adventure: adventure, sheet: sheet
            )
            adventure.update!(combat_context: data)
          end
          adventure.reload
        end

        private

        # Reuse an active row only when its token ids match this encounter's participants.
        # Otherwise archive stale rows and create a fresh grid so a new fight never inherits
        # another encounter's map state.
        def token_sets_match?(stored_tokens, desired_tokens)
          sk = stored_tokens.is_a?(Hash) ? stored_tokens.keys.map(&:to_s).sort : []
          dk = desired_tokens.keys.map(&:to_s).sort
          sk == dk && dk.any?
        end

        def default_world
          { "cells" => {}, "note" => "Sparse square grid; diagonal moves cost 1.5 squares (half-square units in engine)." }
        end

        def default_viewport
          { "min_x" => 0, "min_y" => 0, "width" => 40, "height" => 40 }
        end

        # Window in world space anchored on the player token when present; otherwise a fixed origin.
        # When the player moves, Combat GM / NPC patches should emit shift_viewport (or move the window)
        # — the engine does not auto-follow unless patches update this JSON.
        def viewport_for_tokens(tokens)
          pt = tokens["player"]
          half = 20
          span = 40
          if pt.is_a?(Hash) && pt["x"] && pt["y"]
            px = pt["x"].to_i
            py = pt["y"].to_i
            {
              "min_x" => px - half,
              "min_y" => py - half,
              "width" => span,
              "height" => span,
              "anchor_x" => px,
              "anchor_y" => py
            }
          else
            default_viewport
          end
        end

        # Place tokens on a simple grid for BETA (canonical positions for patches / prompts).
        def build_tokens_from_participants(participants)
          tokens = {}
          Array(participants).each_with_index do |p, i|
            next unless p.is_a?(Hash)
            name = p["name"].to_s.presence || "unknown_#{i}"
            id = token_id_for(p, i)
            x = 18 + (i % 5) * 2
            y = 20 + (i / 5) * 2
            tokens[id] = {
              "label" => name,
              "x" => x,
              "y" => y,
              "creature_sheet_id" => p["creature_sheet_id"],
              "type" => p["type"]
            }.compact
          end
          tokens
        end

        def token_id_for(p, i)
          if p["type"].to_s == "player"
            "player"
          elsif p["creature_sheet_id"].present?
            "creature_#{p['creature_sheet_id']}"
          else
            "token_#{i}_#{p['name'].to_s.parameterize.underscore.presence || 'npc'}"
          end
        end
      end
    end
  end
end
