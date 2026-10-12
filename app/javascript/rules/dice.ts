export interface DiceRollResult {
  natural: number
  modifier: number
  total: number
  isCritical: boolean
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

const DICE_NOTATION = /^(\d+)d(\d+)([+-]\d+)?$/
const FALLBACK_DICE: ParsedDice = { count: 1, sides: 4, flat: 0 }

export function parseDiceNotation(notation: string): ParsedDice {
  const match = notation.match(DICE_NOTATION)
  if (!match) return { ...FALLBACK_DICE }
  return {
    count: parseInt(match[1], 10),
    sides: parseInt(match[2], 10),
    flat: match[3] ? parseInt(match[3], 10) : 0,
  }
}

export function rollParsedDice(parsed: ParsedDice): number[] {
  const rolls: number[] = []
  for (let i = 0; i < parsed.count; i++) {
    rolls.push(Math.floor(Math.random() * parsed.sides) + 1)
  }
  return rolls
}
