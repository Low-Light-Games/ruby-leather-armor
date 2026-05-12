# frozen_string_literal: true

module Authoring
  class BestiaryEntryDraft
    ABILITY_SCORE_RANGE = (1..40).freeze
    AC_RANGE            = (1..50).freeze
    BAB_RANGE           = (0..30).freeze
    SPEED_RANGE         = (0..120).freeze
    CR_RANGE            = (1..30).freeze

    DEFAULT_CR              = 3
    DEFAULT_ABILITY_SCORE   = 10
    DEFAULT_AC              = 10
    DEFAULT_BAB             = 0
    DEFAULT_SPEED           = 30
    DEFAULT_CREATURE_TYPE   = "humanoid"
    DEFAULT_HP_FORMULA      = "3d8"
    HP_FORMULA_PATTERN      = /\A\d+d\d+([+-]\d+)?\z/

    def initialize(raw, story_npc:)
      @raw       = raw.is_a?(Hash) ? raw : {}
      @story_npc = story_npc
    end

    def to_bestiary_attrs
      {
        name:             @story_npc.name,
        creature_type:    @raw["creature_type"].to_s.presence || DEFAULT_CREATURE_TYPE,
        cr:               clamp_int(@raw["cr"], CR_RANGE, default: DEFAULT_CR),
        strength:         clamp_int(@raw["strength"],     ABILITY_SCORE_RANGE, default: DEFAULT_ABILITY_SCORE),
        dexterity:        clamp_int(@raw["dexterity"],    ABILITY_SCORE_RANGE, default: DEFAULT_ABILITY_SCORE),
        constitution:     clamp_int(@raw["constitution"], ABILITY_SCORE_RANGE, default: DEFAULT_ABILITY_SCORE),
        intelligence:     clamp_int(@raw["intelligence"], ABILITY_SCORE_RANGE, default: DEFAULT_ABILITY_SCORE),
        wisdom:           clamp_int(@raw["wisdom"],       ABILITY_SCORE_RANGE, default: DEFAULT_ABILITY_SCORE),
        charisma:         clamp_int(@raw["charisma"],     ABILITY_SCORE_RANGE, default: DEFAULT_ABILITY_SCORE),
        ac:               clamp_int(@raw["ac"],           AC_RANGE,            default: DEFAULT_AC),
        base_attack:      clamp_int(@raw["base_attack"],  BAB_RANGE,           default: DEFAULT_BAB),
        speed:            clamp_int(@raw["speed"],        SPEED_RANGE,         default: DEFAULT_SPEED),
        hp_formula:       normalize_hp_formula(@raw["hp_formula"]),
      }
    end

    private

    def clamp_int(value, range, default:)
      n = Integer(value) rescue nil
      return default if n.nil?

      n.clamp(range.min, range.max)
    end

    def normalize_hp_formula(raw)
      raw = Array(raw).join if raw.is_a?(Array)
      formula = raw.to_s.strip
      return DEFAULT_HP_FORMULA if formula.empty?

      return formula if formula =~ HP_FORMULA_PATTERN

      DEFAULT_HP_FORMULA
    end
  end
end
