/**
 * Dice rolling mechanics for d20 system.
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
