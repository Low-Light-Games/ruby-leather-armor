# frozen_string_literal: true

# Licensing invariant: OGL/SRD content from the Pathfinder Reference
# Document only. Custom or paid-content stat blocks must not land here.
class BestiaryEntry < ApplicationRecord
  self.primary_key = :id

  belongs_to :story, optional: true

  validates :id, :name, :source, presence: true
  validates :default_for_type, uniqueness: true, allow_nil: true

  scope :public_bestiary, -> { where(story_id: nil, default_for_type: nil) }
  scope :for_story,       ->(story) { where(story_id: story.id) }
  scope :default_for,     ->(type) { where(default_for_type: type.to_s) }

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
    CREATURE_TYPE_MAP[raw] || (AdventureActorSheet::CREATURE_TYPES.include?(raw) ? raw : "monster")
  end

  def to_adventure_actor_sheet_attrs(display_name: nil)
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
