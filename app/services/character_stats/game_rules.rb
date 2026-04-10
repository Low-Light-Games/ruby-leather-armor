# frozen_string_literal: true

module CharacterStats
  # Static Pathfinder 1e lookup tables shared across all calculators.
  #
  # Include this module in any calculator class that needs access to the tables.
  # None of the constants carry behaviour — they are pure data.
  module GameRules
    ABILITIES = %w[strength dexterity constitution intelligence wisdom charisma].freeze

    # ── Class data (OGC mechanical tables) ────────────────────────

    CLASS_DATA = {
      "barbarian"  => { hit_die: 12, bab: "full",  good_saves: %w[fort], skill_points: 4 },
      "bard"       => { hit_die: 8,  bab: "3/4",   good_saves: %w[ref will], skill_points: 6 },
      "cleric"     => { hit_die: 8,  bab: "3/4",   good_saves: %w[fort will], skill_points: 2 },
      "druid"      => { hit_die: 8,  bab: "3/4",   good_saves: %w[fort will], skill_points: 4 },
      "fighter"    => { hit_die: 10, bab: "full",   good_saves: %w[fort], skill_points: 2 },
      "monk"       => { hit_die: 8,  bab: "3/4",   good_saves: %w[fort ref will], skill_points: 4 },
      "paladin"    => { hit_die: 10, bab: "full",   good_saves: %w[fort will], skill_points: 2 },
      "ranger"     => { hit_die: 10, bab: "full",   good_saves: %w[fort ref], skill_points: 6 },
      "rogue"      => { hit_die: 8,  bab: "3/4",   good_saves: %w[ref], skill_points: 8 },
      "sorcerer"   => { hit_die: 6,  bab: "1/2",   good_saves: %w[will], skill_points: 2 },
      "wizard"     => { hit_die: 6,  bab: "1/2",   good_saves: %w[will], skill_points: 2 },
    }.freeze

    # ── Race data (OGC mechanical tables) ─────────────────────────

    RACE_DATA = {
      "human"    => { size: "Medium", speed: 30, fixed: {},
                      flex_count: 1, skill_bonuses: {} },
      "elf"      => { size: "Medium", speed: 30,
                      fixed: { "dexterity" => 2, "intelligence" => 2, "constitution" => -2 },
                      flex_count: 0, skill_bonuses: { "Perception" => 2 } },
      "dwarf"    => { size: "Medium", speed: 20,
                      fixed: { "constitution" => 2, "wisdom" => 2, "charisma" => -2 },
                      flex_count: 0, skill_bonuses: {} },
      "halfling" => { size: "Small",  speed: 20,
                      fixed: { "dexterity" => 2, "charisma" => 2, "strength" => -2 },
                      flex_count: 0,
                      skill_bonuses: { "Perception" => 2, "Acrobatics" => 2, "Climb" => 2 } },
      "gnome"    => { size: "Small",  speed: 20,
                      fixed: { "constitution" => 2, "charisma" => 2, "strength" => -2 },
                      flex_count: 0, skill_bonuses: { "Perception" => 2 } },
      "half_elf" => { size: "Medium", speed: 30, fixed: {},
                      flex_count: 1, skill_bonuses: { "Perception" => 2 } },
      "half_orc" => { size: "Medium", speed: 30, fixed: {},
                      flex_count: 1, skill_bonuses: { "Intimidate" => 2 } },
    }.freeze

    # ── Carry capacity table (OGC) — indexed by STR score ─────────
    # Each entry: [light_load_max, medium_load_max, heavy_load_max]
    CARRY_CAPACITY = [
      [0, 0, 0],          # STR 0
      [3, 6, 10],         # STR 1
      [6, 13, 20],        # STR 2
      [10, 20, 30],       # STR 3
      [13, 26, 40],       # STR 4
      [16, 33, 50],       # STR 5
      [20, 40, 60],       # STR 6
      [23, 46, 70],       # STR 7
      [26, 53, 80],       # STR 8
      [30, 60, 90],       # STR 9
      [33, 66, 100],      # STR 10
      [38, 76, 115],      # STR 11
      [43, 86, 130],      # STR 12
      [50, 100, 150],     # STR 13
      [58, 116, 175],     # STR 14
      [66, 133, 200],     # STR 15
      [76, 153, 230],     # STR 16
      [86, 173, 260],     # STR 17
      [100, 200, 300],    # STR 18
      [116, 233, 350],    # STR 19
      [133, 266, 400],    # STR 20
      [153, 306, 460],    # STR 21
      [173, 346, 520],    # STR 22
      [200, 400, 600],    # STR 23
      [233, 466, 700],    # STR 24
      [266, 533, 800],    # STR 25
      [306, 613, 920],    # STR 26
      [346, 693, 1040],   # STR 27
      [400, 800, 1200],   # STR 28
      [466, 933, 1400],   # STR 29
    ].freeze

    # ── Skill table (OGC) ─────────────────────────────────────────

    SKILLS = [
      { name: "Acrobatics",                key: "dexterity",     trained_only: false, acp: true },
      { name: "Appraise",                  key: "intelligence",  trained_only: false, acp: false },
      { name: "Bluff",                     key: "charisma",      trained_only: false, acp: false },
      { name: "Climb",                     key: "strength",      trained_only: false, acp: true },
      { name: "Craft",                     key: "intelligence",  trained_only: false, acp: false },
      { name: "Diplomacy",                 key: "charisma",      trained_only: false, acp: false },
      { name: "Disable Device",            key: "dexterity",     trained_only: true,  acp: true },
      { name: "Disguise",                  key: "charisma",      trained_only: false, acp: false },
      { name: "Escape Artist",             key: "dexterity",     trained_only: false, acp: true },
      { name: "Fly",                       key: "dexterity",     trained_only: false, acp: true },
      { name: "Handle Animal",             key: "charisma",      trained_only: true,  acp: false },
      { name: "Heal",                      key: "wisdom",        trained_only: false, acp: false },
      { name: "Intimidate",               key: "charisma",      trained_only: false, acp: false },
      { name: "Knowledge (Arcana)",        key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Dungeoneering)", key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Engineering)",   key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Geography)",     key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (History)",       key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Local)",         key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Nature)",        key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Nobility)",      key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Planes)",        key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Religion)",      key: "intelligence",  trained_only: true,  acp: false },
      { name: "Linguistics",               key: "intelligence",  trained_only: true,  acp: false },
      { name: "Perception",                key: "wisdom",        trained_only: false, acp: false },
      { name: "Perform",                   key: "charisma",      trained_only: false, acp: false },
      { name: "Profession",                key: "wisdom",        trained_only: true,  acp: false },
      { name: "Ride",                      key: "dexterity",     trained_only: false, acp: true },
      { name: "Sense Motive",              key: "wisdom",        trained_only: false, acp: false },
      { name: "Sleight of Hand",           key: "dexterity",     trained_only: true,  acp: true },
      { name: "Spellcraft",               key: "intelligence",  trained_only: true,  acp: false },
      { name: "Stealth",                   key: "dexterity",     trained_only: false, acp: true },
      { name: "Survival",                  key: "wisdom",        trained_only: false, acp: false },
      { name: "Swim",                      key: "strength",      trained_only: false, acp: true },
      { name: "Use Magic Device",          key: "charisma",      trained_only: true,  acp: false },
    ].freeze
  end
end
