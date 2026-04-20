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
            # Always start from a new row: never reuse an active map (terrain/viewport/token
            # positions) even when token ids match — rematches, retries, and missed archives
            # would otherwise inherit the previous encounter's spatial state.
            adventure.adventure_battlefields.where(status: "active").find_each(&:archive!)

            bf = adventure.adventure_battlefields.create!(
              status: "active",
              topology: "square",
              world: default_world(adventure),
              tokens: desired_tokens,
              viewport: viewport_for_tokens(desired_tokens),
              version: 1
            )
            battlefield_reference = BattlefieldReference.from_battlefield(bf)

            payload = DungeonMaster::Battlefield::CombatContextPayload.new(
              base_data: data,
              battlefield_reference: battlefield_reference,
              action_economy_builder: method(:default_action_economy)
            )
            adventure.update!(combat_context: payload.to_h)
          end
          adventure.reload
        end

        # True when an active battlefield's token ids match the roster in +participants+
        # (same ids PersistCombatStart would build). Used by EnsureForActiveCombat to avoid
        # binding a combat to an unrelated stray row.
        def same_token_set_as_participants?(bf_tokens, participants)
          desired = build_tokens_from_participants(Array(participants))
          token_sets_match?(bf_tokens, desired)
        end

        private

        def token_sets_match?(stored_tokens, desired_tokens)
          sk = stored_tokens.is_a?(Hash) ? stored_tokens.keys.map(&:to_s).sort : []
          dk = desired_tokens.keys.map(&:to_s).sort
          sk == dk && dk.any?
        end

        def default_world(adventure = nil)
          note_parts = ["Sparse square grid; diagonal moves cost 1.5 squares (half-square units in engine)."]
          if adventure
            note_parts << "Location: #{adventure.current_location&.name}." if adventure.current_location&.name.present?
            note_parts << "Scene: #{adventure.scene_summary}." if adventure.scene_summary.present?
          end
          { "cells" => {}, "note" => note_parts.join(" ") }
        end

        def default_viewport
          { "min_x" => 0, "min_y" => 0, "width" => 40, "height" => 40 }
        end

        # Window in world space anchored on the player token when present; otherwise a fixed origin.
        # When the player moves, Combat GM / NPC patches should emit shift_viewport (or move the window)
        # — the engine does not auto-follow unless patches update this JSON.
        def viewport_for_tokens(tokens)
          player_token = tokens["player"]
          half = 20
          span = 40
          if player_token_with_coordinates?(player_token)
            px = player_token["x"].to_i
            py = player_token["y"].to_i
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

        def player_token_with_coordinates?(player_token)
          player_token.is_a?(Hash) && player_token["x"] && player_token["y"]
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

        def default_action_economy(combat_context)
          holder = combat_context["current_turn"].presence || DungeonMaster::Utilities::CombatTurnCalculator::PLAYER_NAME
          ActionEconomy.build_for_turn_holder(holder, combat_ctx: combat_context)
        end
      end
    end
  end
end
