import type { AttributeType } from '../types'
import type { OwnedItem, Currency } from '../rules/pathfinder_items_types'
import type { SkillRanksMap } from '../rules/pathfinder_skill_ranks'

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
