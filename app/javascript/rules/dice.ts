/**
 * Dice rolling mechanics for d20 system and generic damage dice.
 * Pure game mechanics — Open Game Content.
 */

export interface DiceRollResult {
  /** The natural d20 result (1–20) */
  natural: number
  /** The modifier applied */
  modifier: number
  /** The total result (natural + modifier) */
  total: number
  /** Whether it was a natural 20 */
  isCritical: boolean
  /** Whether it was a natural 1 */
  isFumble: boolean
}

export interface ParsedDice {
  count: number
  sides: number
  flat: number
}

export interface DamageRollResult {
  rolls: number[]
  diceNotation: string
  flatBonus: number
  bonusBreakdown: string[]
  total: number
  damageType: string
  label: string
}

/**
 * Roll a d20 and apply a modifier.
 */
export function rollD20(modifier: number): DiceRollResult {
  const natural = Math.floor(Math.random() * 20) + 1
  return {
    natural,
    modifier,
    total: natural + modifier,
    isCritical: natural === 20,
    isFumble: natural === 1,
  }
}

/** Parse notation like "1d8", "2d6+3", "1d4+1", "1d3" */
export function parseDiceNotation(notation: string): ParsedDice {
  const match = notation.match(/^(\d+)d(\d+)([+-]\d+)?$/)
  if (!match) return { count: 1, sides: 4, flat: 0 }
  return {
    count: parseInt(match[1], 10),
    sides: parseInt(match[2], 10),
    flat: match[3] ? parseInt(match[3], 10) : 0,
  }
}

/** Roll arbitrary dice from a ParsedDice spec. Returns individual rolls. */
export function rollParsedDice(parsed: ParsedDice): number[] {
  const rolls: number[] = []
  for (let i = 0; i < parsed.count; i++) {
    rolls.push(Math.floor(Math.random() * parsed.sides) + 1)
  }
  return rolls
}
