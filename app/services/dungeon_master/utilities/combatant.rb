# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # Value object for one participant in a combat encounter (player or NPC).
    # Used by Warmaster, CombatTurnCalculator, WorldTurn, and combat_context serialization.
    class Combatant
      attr_reader :name, :creature_sheet_id, :type, :initiative,
                  :hp, :max_hp, :conditions, :position

      def initialize(name:, creature_sheet_id:, type:, initiative:,
        hp:, max_hp:, conditions: [], position: nil)
        @name = name.to_s
        @creature_sheet_id = creature_sheet_id
        @type = type.to_s
        @initiative = initiative.to_i
        @hp = hp.to_i
        @max_hp = max_hp.to_i
        @conditions = Array(conditions).map(&:to_s)
        @position = position
      end

      def defeated?
        hp <= 0 || conditions.include?("dead")
      end

      # PF1e dying: player at negative HP, not yet at −CON. CON threshold is checked by
      # CombatEndResolver against the live sheet; this is purely HP-sign based.
      def dying?
        hp < 0 && !conditions.include?("dead")
      end

      # Out of the fight for good (not merely stunned/paralyzed this round).
      # NPCs are eliminated at 0 HP; players must reach the "dead" condition (−CON) to
      # leave the encounter — a dying player is incapacitated but still in the fight.
      def eliminated_from_encounter?
        return conditions.include?("dead") ||
               conditions.include?("fled") ||
               conditions.include?("surrendered") if player?

        defeated? ||
          conditions.include?("fled") ||
          conditions.include?("surrendered")
      end

      def can_act?
        hp > 0 &&
          !conditions.include?("fled") &&
          !conditions.include?("surrendered") &&
          !conditions.include?("paralyzed") &&
          !conditions.include?("petrified")
      end

      def player?
        type == "player"
      end

      def npc?
        type == "npc"
      end

      def to_context_hash
        context_hash = base_context_hash
        context_hash["creature_sheet_id"] = creature_sheet_id if creature_sheet_id.present?
        context_hash
      end

      def self.from_creature_sheet(sheet, initiative:)
        new(
          name: sheet.name,
          creature_sheet_id: sheet.id,
          type: "npc",
          initiative: initiative,
          hp: sheet.hp,
          max_hp: sheet.max_hp,
          conditions: Array(sheet.conditions),
          position: nil
        )
      end

      def self.from_player_sheet(sheet, initiative:)
        new(
          name: "Player",
          creature_sheet_id: nil,
          type: "player",
          initiative: initiative,
          hp: sheet.hp,
          max_hp: sheet.max_hp,
          conditions: Array(sheet.conditions),
          position: nil
        )
      end

      # Deserialize from combat_context participant hash (string keys).
      def self.from_context_hash(hash)
        h = hash.stringify_keys
        new(
          name: h["name"],
          creature_sheet_id: h["creature_sheet_id"],
          type: h["type"] || "npc",
          initiative: h["initiative"].to_i,
          hp: h["hp"].to_i,
          max_hp: (h["max_hp"] || h["hp"]).to_i,
          conditions: Array(h["conditions"]),
          position: h["position"]
        )
      end

      def self.refresh_from_live_sources(hash, adventure:, sheet:)
        combatant = from_context_hash(hash)

        if combatant.player? && sheet
          from_player_sheet(sheet, initiative: combatant.initiative).to_context_hash
        elsif combatant.creature_sheet_id.present?
          creature = adventure.creature_sheets.find_by(id: combatant.creature_sheet_id)
          creature ? from_creature_sheet(creature, initiative: combatant.initiative).to_context_hash : combatant.to_context_hash
        else
          combatant.to_context_hash
        end
      end

      def base_context_hash
        {
          "name" => name,
          "type" => type,
          "initiative" => initiative,
          "hp" => hp,
          "max_hp" => max_hp,
          "conditions" => conditions,
          "position" => position
        }
      end
    end
  end
end
