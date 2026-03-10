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

  CREATURE_TYPE_MAP = {
    "humanoid"          => "npc",
    "monstrous humanoid"=> "npc",
    "npc"               => "npc",
    "animal"            => "animal",
    "beast"             => "beast",
    "magical beast"     => "beast",
    "dragon"            => "beast",
    "monster"           => "monster",
    "undead"            => "monster",
    "construct"         => "monster",
    "aberration"        => "monster",
    "outsider"          => "monster",
    "elemental"         => "monster",
    "fey"               => "monster",
    "ooze"              => "monster",
    "plant"             => "monster",
    "vermin"            => "monster",
  }.freeze

  def normalized_creature_type
    raw = creature_type.to_s.downcase.strip
    CREATURE_TYPE_MAP[raw] || (CreatureSheet::CREATURE_TYPES.include?(raw) ? raw : "monster")
  end

  def to_creature_sheet_attrs(display_name: nil)
    {
      name: display_name || name,
      creature_type: normalized_creature_type,
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
