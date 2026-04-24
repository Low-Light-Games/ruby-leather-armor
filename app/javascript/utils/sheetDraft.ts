import type { AttributeType } from '../types'
import type { OwnedItem, Currency } from '../rules/pathfinder_items_types'
import type { SkillRanksMap } from '../rules/pathfinder_skill_ranks'
import { EMPTY_CURRENCY } from '../rules/pathfinder_items'

const SHEET_DRAFT_VERSION = 1

export interface SheetDraftData {
  name: string
  description: string
  attributes: Record<AttributeType, number>
  race: string | null
  flexibleBonus: AttributeType | null
  characterClass: string | null
  level: number
  feats: string[]
  spells: string[]
  items: OwnedItem[]
  currency: Currency
  skillRanks: SkillRanksMap
}

/**
 * Single source of truth for a new blank character (draft shape + builder defaults).
 * Use `emptySheetDraft()` for a mutable copy; use `BLANK_CHARACTER_ATTRIBUTES` for default scores.
 */
const BLANK_SHEET: SheetDraftData = {
  name: '',
  description: '',
  attributes: {
    strength: 10,
    intelligence: 10,
    dexterity: 10,
    constitution: 10,
    wisdom: 10,
    charisma: 10,
  },
  race: null,
  flexibleBonus: null,
  characterClass: null,
  level: 1,
  feats: [],
  spells: [],
  items: [],
  currency: { ...EMPTY_CURRENCY },
  skillRanks: {},
}

const ATTRIBUTE_KEYS = Object.keys(BLANK_SHEET.attributes) as AttributeType[]

/** Default ability scores for a new character (`emptySheetDraft().attributes`). */
export const BLANK_CHARACTER_ATTRIBUTES: SheetDraftData['attributes'] = { ...BLANK_SHEET.attributes }

interface StoredSheetDraft {
  version: number
  savedAt: string
  data: SheetDraftData
}

function draftKey(userId: number): string {
  return `sheet-draft:v${SHEET_DRAFT_VERSION}:user:${userId}`
}

export function loadSheetDraft(userId: number): SheetDraftData | null {
  const raw = window.localStorage.getItem(draftKey(userId))
  if (!raw) return null

  try {
    const parsed = JSON.parse(raw) as StoredSheetDraft
    if (parsed.version !== SHEET_DRAFT_VERSION || !parsed.data) {
      window.localStorage.removeItem(draftKey(userId))
      return null
    }

    return parsed.data
  } catch {
    window.localStorage.removeItem(draftKey(userId))
    return null
  }
}

export function saveSheetDraft(userId: number, data: SheetDraftData): void {
  const payload: StoredSheetDraft = {
    version: SHEET_DRAFT_VERSION,
    savedAt: new Date().toISOString(),
    data,
  }

  window.localStorage.setItem(draftKey(userId), JSON.stringify(payload))
}

export function clearSheetDraft(userId: number): void {
  window.localStorage.removeItem(draftKey(userId))
}

/** Deep enough clone for draft fields (arrays/objects copied shallowly where draft is flat). */
export function emptySheetDraft(): SheetDraftData {
  return {
    name: BLANK_SHEET.name,
    description: BLANK_SHEET.description,
    attributes: { ...BLANK_SHEET.attributes },
    race: BLANK_SHEET.race,
    flexibleBonus: BLANK_SHEET.flexibleBonus,
    characterClass: BLANK_SHEET.characterClass,
    level: BLANK_SHEET.level,
    feats: [...BLANK_SHEET.feats],
    spells: [...BLANK_SHEET.spells],
    items: [...BLANK_SHEET.items],
    currency: { ...BLANK_SHEET.currency },
    skillRanks: { ...BLANK_SHEET.skillRanks },
  }
}

function currencyEquals(a: Currency, b: Currency): boolean {
  return (
    a.gold === b.gold &&
    a.silver === b.silver &&
    a.copper === b.copper &&
    a.platinum === b.platinum
  )
}

/** True when the draft matches the known empty sheet (nothing worth persisting). */
export function isKnownEmptySheetDraft(data: SheetDraftData): boolean {
  if (data.name.trim() !== '' || (data.description || '').trim() !== '') return false
  if (data.race != null || data.flexibleBonus != null || data.characterClass != null) return false
  if (data.level !== BLANK_SHEET.level) return false
  if (data.feats.length > 0 || data.spells.length > 0 || data.items.length > 0) return false
  if (Object.keys(data.skillRanks || {}).length > 0) return false
  if (!currencyEquals(data.currency || EMPTY_CURRENCY, BLANK_SHEET.currency)) return false
  for (const key of ATTRIBUTE_KEYS) {
    if (data.attributes[key] !== BLANK_SHEET.attributes[key]) return false
  }
  return true
}
