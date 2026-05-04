import type { SeedFact } from '../types'

export interface SeedFactsSectionProps {
  seedFacts: SeedFact[]
  setSeedFacts: React.Dispatch<React.SetStateAction<SeedFact[]>>
  open: boolean
  setOpen: (open: boolean) => void
}
