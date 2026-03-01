# frozen_string_literal: true

# OGL/SRD-only creature templates from the Pathfinder Reference Document.
# Used to deterministically create CreatureSheet instances at runtime.
class BestiaryEntry < ApplicationRecord
  self.primary_key = :id

  validates :id, :name, :source, presence: true

  def modifier_for(ability)
    score = send(ability)
    ((score - 10).to_f / 2).floor
  end

  def to_creature_sheet_attrs(display_name: nil)
    {
      name: display_name || name,
      creature_type: creature_type || "npc",
      strength: strength, dexterity: dexterity, constitution: constitution,
      intelligence: intelligence, wisdom: wisdom, charisma: charisma,
      level: [cr.to_i, 1].max,
      derived_stats: {
        "ac" => ac, "bab" => base_attack, "speed" => speed,
        "cmb" => base_attack + modifier_for(:strength),
        "cmd" => 10 + base_attack + modifier_for(:strength) + modifier_for(:dexterity)
      }
    }
  end
end
