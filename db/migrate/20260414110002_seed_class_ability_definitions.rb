# frozen_string_literal: true

class SeedClassAbilityDefinitions < ActiveRecord::Migration[7.1]
  STAPLES = [
    # Barbarian
    { id: "rage",          name: "Rage",          pf1e_class: "barbarian",  summary: "Enter a powerful battle rage, gaining bonus to Str/Con and Will saves." },
    { id: "greater_rage",  name: "Greater Rage",  pf1e_class: "barbarian",  summary: "Enhanced rage with larger bonuses than standard Rage." },
    { id: "mighty_rage",   name: "Mighty Rage",   pf1e_class: "barbarian",  summary: "Maximum rage bonuses, available at high barbarian levels." },
    # Paladin
    { id: "smite_evil",    name: "Smite Evil",    pf1e_class: "paladin",    summary: "Add Cha bonus to attack and level bonus to damage against an evil target." },
    { id: "lay_on_hands",  name: "Lay on Hands",  pf1e_class: "paladin",    summary: "Heal hit points with a touch, a number of times per day." },
    { id: "divine_bond",   name: "Divine Bond",   pf1e_class: "paladin",    summary: "Form a bond with a mount or weapon, granting it magical enhancements." },
    # Cleric
    { id: "channel_energy", name: "Channel Energy", pf1e_class: "cleric",   summary: "Release a burst of positive or negative energy to heal or harm." },
    # Bard
    { id: "bardic_performance", name: "Bardic Performance", pf1e_class: "bard", summary: "Use performance to inspire allies or hinder enemies." },
    { id: "inspire_courage",    name: "Inspire Courage",    pf1e_class: "bard", summary: "Boost attack, damage, and save bonuses for allies via performance." },
    # Druid
    { id: "wild_shape",    name: "Wild Shape",    pf1e_class: "druid",      summary: "Polymorph into an animal or elemental form." },
    # Monk
    { id: "flurry_of_blows", name: "Flurry of Blows", pf1e_class: "monk",  summary: "Make a full attack with additional unarmed strikes at a penalty." },
    { id: "stunning_fist",   name: "Stunning Fist",   pf1e_class: "monk",  summary: "Attempt to stun a target with an unarmed strike." },
    { id: "ki_strike",       name: "Ki Strike",       pf1e_class: "monk",  summary: "Unarmed strikes count as magic (and later adamantine/lawful) for DR." },
    { id: "ki_pool",         name: "Ki Pool",         pf1e_class: "monk",  summary: "Pool of ki points powering special monk abilities." },
    { id: "evasion",         name: "Evasion",         pf1e_class: "monk",  summary: "Take no damage on successful Reflex save against area attacks." },
    # Rogue
    { id: "sneak_attack",    name: "Sneak Attack",    pf1e_class: "rogue",  summary: "Deal extra dice of damage when flanking or target is denied Dex bonus." },
    { id: "uncanny_dodge",   name: "Uncanny Dodge",   pf1e_class: "rogue",  summary: "Retain Dex bonus to AC even when caught flat-footed." },
    # Inquisitor
    { id: "judgment",        name: "Judgment",        pf1e_class: "inquisitor", summary: "Declare a judgment granting bonuses to attack, damage, saves, or AC." },
    # Magus
    { id: "spellstrike",     name: "Spellstrike",     pf1e_class: "magus",  summary: "Deliver a touch spell through a melee weapon attack." },
    { id: "spell_combat",    name: "Spell Combat",    pf1e_class: "magus",  summary: "Cast a spell and make a full attack in the same round." },
    { id: "arcane_pool",     name: "Arcane Pool",     pf1e_class: "magus",  summary: "Pool of arcane points to enhance weapons or power magus abilities." },
    # Ranger
    { id: "favored_enemy",   name: "Favored Enemy",   pf1e_class: "ranger", summary: "Gain bonus to attack, damage, and skill checks against chosen creature type." },
    { id: "hunters_bond",    name: "Hunter's Bond",   pf1e_class: "ranger", summary: "Bond with a companion animal or share favored enemy bonuses with allies." }
  ].freeze

  def up
    STAPLES.each do |attrs|
      execute <<~SQL
        INSERT INTO class_ability_definitions (id, name, pf1e_class, summary, created_at, updated_at)
        VALUES (
          #{quote(attrs[:id])},
          #{quote(attrs[:name])},
          #{quote(attrs[:pf1e_class])},
          #{quote(attrs[:summary])},
          NOW(), NOW()
        )
        ON CONFLICT (id) DO UPDATE SET
          name       = EXCLUDED.name,
          pf1e_class = EXCLUDED.pf1e_class,
          summary    = EXCLUDED.summary,
          updated_at = NOW()
      SQL
    end
  end

  def down
    ids = STAPLES.map { |a| quote(a[:id]) }.join(", ")
    execute "DELETE FROM class_ability_definitions WHERE id IN (#{ids})"
  end

  private

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
