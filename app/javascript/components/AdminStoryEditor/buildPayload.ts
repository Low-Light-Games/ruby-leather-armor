import type {
  ClientLocation,
  EncounterTableData, StoryNpcData, StoryClueData, StoryMilestoneData,
  InitialContexts, SeedFact,
  TraversalCtx, CombatCtx, SocialCtx, ExplorationCtx, RestCtx, InventoryCtx,
} from './types'

export interface PayloadArgs {
  title: string
  preview: string
  premise: string
  openingMessage: string
  seedFacts: SeedFact[]
  initialSummary: string
  currentStoryId: number | undefined
  locations: ClientLocation[]
  encounterTables: EncounterTableData[]
  npcs: StoryNpcData[]
  clues: StoryClueData[]
  milestones: StoryMilestoneData[]
  icTraversal: TraversalCtx
  icCombat: CombatCtx
  icSocial: SocialCtx
  icExploration: ExplorationCtx
  icRest: RestCtx
  icInventory: InventoryCtx
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

const stripEmpty = (obj: Record<string, unknown>): Record<string, unknown> | null => {
  const clean: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(obj)) {
    if (v === '' || v === null || v === undefined) continue
    if (Array.isArray(v) && v.length === 0) continue
    if (typeof v === 'boolean' && !v) continue
    clean[k] = v
  }
  return Object.keys(clean).length > 0 ? clean : null
}

export const buildInitialContextsPayload = (
  icTraversal: TraversalCtx,
  icCombat: CombatCtx,
  icSocial: SocialCtx,
  icExploration: ExplorationCtx,
  icRest: RestCtx,
  icInventory: InventoryCtx,
): InitialContexts => {
  const ic: Record<string, unknown> = {}
  const t = stripEmpty(icTraversal as unknown as Record<string, unknown>)
  if (t) ic.traversal_context = t
  const c = stripEmpty(icCombat as unknown as Record<string, unknown>)
  if (c) ic.combat_context = c
  const s = stripEmpty({ ...icSocial, npcs_present: icSocial.npcs_present.length > 0 ? icSocial.npcs_present : undefined } as unknown as Record<string, unknown>)
  if (s) ic.social_context = s
  const e = stripEmpty(icExploration as unknown as Record<string, unknown>)
  if (e) ic.exploration_context = e
  const r = stripEmpty(icRest as unknown as Record<string, unknown>)
  if (r) ic.rest_context = r
  const inv = stripEmpty(icInventory as unknown as Record<string, unknown>)
  if (inv) ic.inventory_context = inv
  return ic as InitialContexts
}

export const buildPayload = (args: PayloadArgs) => {
  const {
    title, preview, premise, openingMessage, seedFacts, initialSummary,
    currentStoryId, locations, encounterTables, npcs, clues, milestones,
    icTraversal, icCombat, icSocial, icExploration, icRest, icInventory,
  } = args

  const story: Record<string, unknown> = {
    title, preview, premise,
    opening_message: openingMessage,
    seed_facts: seedFacts,
    initial_summary: initialSummary,
    initial_contexts: buildInitialContextsPayload(
      icTraversal, icCombat, icSocial, icExploration, icRest, icInventory,
    ),
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
      return attrs
    })

    story.story_clues_attributes = clues.map(clue => {
      const attrs: Record<string, unknown> = {
        source: clue.source, title: clue.title, description: clue.description,
        discovery_method: clue.discovery_method, location_id: clue.location_id || null,
        npc_id: clue.npc_id || null, prerequisite_clue_ids: clue.prerequisite_clue_ids,
        reveals_secret: clue.reveals_secret, difficulty: clue.difficulty,
      }
      if (clue.id) attrs.id = clue.id
      if (clue._destroy) attrs._destroy = true
      return attrs
    })

    story.story_milestones_attributes = milestones.map(ms => {
      const attrs: Record<string, unknown> = {
        source: ms.source, title: ms.title, description: ms.description,
        trigger_clue_ids: ms.trigger_clue_ids, consequence: ms.consequence,
      }
      if (ms.id) attrs.id = ms.id
      if (ms._destroy) attrs._destroy = true
      return attrs
    })
  }

  return { story }
}
