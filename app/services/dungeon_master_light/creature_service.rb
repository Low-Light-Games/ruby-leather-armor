# frozen_string_literal: true

module DungeonMasterLight
  # Manages creature/NPC sheets and social mechanics for the Light DM system.
  # Handles creation, attitude tracking, and Pathfinder 1e social DC computation.
  class CreatureService
    ATTITUDES = CreatureSheet::ATTITUDES

    # Diplomacy DCs to shift attitude one step (base DC + creature's CHA mod).
    DIPLOMACY_DCS = {
      "hostile" => 25,
      "unfriendly" => 20,
      "indifferent" => 15,
      "friendly" => 10
    }.freeze

    def initialize(adventure)
      @adventure = adventure
    end

    # Idempotent NPC creation. Returns existing if name matches.
    # @return [CreatureSheet]
    def find_or_create_npc(name:, attitude: "indifferent", creature_type: "npc", details: {}, **attrs)
      @adventure.creature_sheets.find_or_create_by!(name: name) do |cs|
        cs.creature_type = creature_type
        cs.attitude = attitude
        cs.details = details
        cs.level = attrs[:level] || 1
        cs.race = attrs[:race] || "human"
        cs.character_class = attrs[:character_class]
        cs.strength = attrs[:strength] || 10
        cs.dexterity = attrs[:dexterity] || 10
        cs.constitution = attrs[:constitution] || 10
        cs.intelligence = attrs[:intelligence] || 10
        cs.wisdom = attrs[:wisdom] || 10
        cs.charisma = attrs[:charisma] || 10
      end
    end

    # @return [String, nil] the attitude, or nil if NPC not found
    def get_attitude(npc_name)
      npc = @adventure.creature_sheets.find_by(name: npc_name)
      npc&.attitude
    end

    # Shift attitude along the scale.
    # @param creature_sheet [CreatureSheet]
    # @param direction [:better, :worse]
    # @param steps [Integer]
    # @return [String] new attitude
    def shift_attitude(creature_sheet, direction:, steps: 1)
      creature_sheet.shift_attitude!(direction, steps: steps)
      creature_sheet.attitude
    end

    # Compute the Diplomacy DC to shift an NPC's attitude one step better.
    # DC = base DC + NPC's CHA modifier
    #
    # @param creature_sheet [CreatureSheet]
    # @param steps [Integer] how many steps to shift (2 adds +10)
    # @return [Integer, nil] nil if already at max (helpful)
    def diplomacy_dc(creature_sheet, steps: 1)
      base = DIPLOMACY_DCS[creature_sheet.attitude]
      return nil unless base

      cha_mod = ((creature_sheet.charisma - 10).to_f / 2).floor
      dc = base + cha_mod
      dc += 10 if steps >= 2

      dc
    end

    # Compute the Intimidate DC to demoralize a creature.
    # DC = 10 + HD (level) + WIS modifier
    #
    # @param creature_sheet [CreatureSheet]
    # @return [Integer]
    def intimidate_dc(creature_sheet)
      wis_mod = ((creature_sheet.wisdom - 10).to_f / 2).floor
      10 + creature_sheet.level + wis_mod
    end

    # Attempt a Diplomacy check to shift attitude.
    # @param creature_sheet [CreatureSheet]
    # @param roll_total [Integer] player's Diplomacy check result (d20 + modifiers)
    # @param steps [Integer]
    # @return [Hash] { success:, new_attitude:, dc:, margin: }
    def attempt_diplomacy(creature_sheet, roll_total:, steps: 1)
      dc = diplomacy_dc(creature_sheet, steps: steps)
      return { success: false, error: "NPC is already at maximum attitude (helpful)" } unless dc

      margin = roll_total - dc

      if margin >= 0
        shift_attitude(creature_sheet, direction: :better, steps: steps)
        { success: true, new_attitude: creature_sheet.attitude, dc: dc, margin: margin }
      elsif margin <= -5
        shift_attitude(creature_sheet, direction: :worse, steps: 1)
        { success: false, new_attitude: creature_sheet.attitude, dc: dc, margin: margin, worsened: true }
      else
        { success: false, new_attitude: creature_sheet.attitude, dc: dc, margin: margin }
      end
    end

    # Attempt an Intimidate check to demoralize.
    # @param creature_sheet [CreatureSheet]
    # @param roll_total [Integer]
    # @return [Hash] { success:, dc:, rounds_shaken: }
    def attempt_intimidate(creature_sheet, roll_total:)
      dc = intimidate_dc(creature_sheet)
      margin = roll_total - dc

      if margin >= 0
        rounds = 1 + (margin / 5)
        { success: true, dc: dc, rounds_shaken: rounds, margin: margin }
      else
        { success: false, dc: dc, rounds_shaken: 0, margin: margin }
      end
    end
  end
end
