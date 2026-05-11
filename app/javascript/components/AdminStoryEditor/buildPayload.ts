import type {
  ClientLocation,
  EncounterTableData, StoryNpcData,
  SeedFact,
} from './types'

export interface PayloadArgs {
  title: string
  preview: string
  premise: string
  openingMessage: string
  seedFacts: SeedFact[]
  currentStoryId: number | undefined
  locations: ClientLocation[]
  encounterTables: EncounterTableData[]
  npcs: StoryNpcData[]
}

export const buildLocationPayload = (locations: ClientLocation[]) =>
  locations.map(loc => {
    const locAttrs: Record<string, unknown> = {
      name: loc.name, description: loc.description, starting: loc.starting,
    }
    if (loc.id) locAttrs.id = loc.id
    if (loc._destroy) locAttrs._destroy = true
    return locAttrs
  })

export const buildPayload = (args: PayloadArgs) => {
  const {
    title, preview, premise, openingMessage, seedFacts,
    currentStoryId, locations, encounterTables, npcs,
  } = args

  const story: Record<string, unknown> = {
    title, preview, premise,
    opening_message: openingMessage,
    seed_facts: seedFacts,
  }

  if (currentStoryId) {
    story.story_locations_attributes = buildLocationPayload(locations)

    story.encounter_tables_attributes = encounterTables.map(table => {
      const tAttrs: Record<string, unknown> = {
        name: table.name, description: table.description,
        check_frequency_hours: table.check_frequency_hours,
        encounter_chance: table.encounter_chance,
      }
      if (table.id) tAttrs.id = table.id
      if (table._destroy) tAttrs._destroy = true

      tAttrs.encounter_table_entries_attributes = (table.encounter_table_entries || []).map(entry => {
        const eAttrs: Record<string, unknown> = {
          title: entry.title, description: entry.description,
          entry_type: entry.entry_type, weight: entry.weight,
          terrain_types: entry.terrain_types || '',
          min_party_level: entry.min_party_level,
          max_party_level: entry.max_party_level,
        }
        if (entry.id) eAttrs.id = entry.id
        if (entry._destroy) eAttrs._destroy = true
        return eAttrs
      })

      return tAttrs
    })

    story.story_npcs_attributes = npcs.map(npc => {
      const attrs: Record<string, unknown> = {
        source: npc.source, name: npc.name, role: npc.role,
        location_id: npc.location_id || null, description: npc.description,
        knowledge: npc.knowledge, attitude: npc.attitude, secret: npc.secret,
      }
      if (npc.id) attrs.id = npc.id
      if (npc._destroy) attrs._destroy = true

      const sheet = npc.bestiary_entry
      if (sheet && sheet.id) {
        attrs.bestiary_entry_attributes = {
          id: sheet.id,
          name: sheet.name, creature_type: sheet.creature_type, cr: sheet.cr,
          alignment: sheet.alignment, size: sheet.size,
          strength: sheet.strength, dexterity: sheet.dexterity,
          constitution: sheet.constitution, intelligence: sheet.intelligence,
          wisdom: sheet.wisdom, charisma: sheet.charisma,
          ac: sheet.ac, hp_formula: sheet.hp_formula,
          base_attack: sheet.base_attack, speed: sheet.speed,
          description: sheet.description, source: sheet.source,
        }
      }
      return attrs
    })
  }

  return { story }
}
