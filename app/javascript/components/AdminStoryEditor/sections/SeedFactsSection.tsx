import CollapsibleSection from '../components/CollapsibleSection'
import type { SeedFact } from '../types'

interface SeedFactsSectionProps {
  seedFacts: SeedFact[]
  setSeedFacts: React.Dispatch<React.SetStateAction<SeedFact[]>>
  open: boolean
  setOpen: (open: boolean) => void
}

const FACT_KINDS: SeedFact['kind'][] = ['event', 'state', 'entity']

const SeedFactsSection = ({ seedFacts, setSeedFacts, open, setOpen }: SeedFactsSectionProps) => {
  const updateFact = (idx: number, patch: Partial<SeedFact>) => {
    setSeedFacts(prev => prev.map((f, i) => (i === idx ? { ...f, ...patch } : f)))
  }

  const removeFact = (idx: number) => {
    setSeedFacts(prev => prev.filter((_, i) => i !== idx))
  }

  const addFact = () => {
    setSeedFacts(prev => [...prev, { text: '', kind: 'event', polarity: 'asserts', entities: [] }])
  }

  return (
    <CollapsibleSection
      label="Seed Facts"
      count={seedFacts.length}
      open={open}
      onToggle={() => setOpen(!open)}
      hint="Durable narrative facts auto-extracted from premise + opening message at save time. Bulk-inserted into the adventure's narrative facts store at adventure creation. Editable — review what the extractor produced before saving."
      emptyHint="No seed facts yet. Save the story to extract facts from the premise."
      isEmpty={seedFacts.length === 0}
    >
      {seedFacts.map((fact, idx) => (
        <div key={idx} className="nested-card">
          <div className="nested-card-body">
            <div style={{ display: 'flex', gap: 8, marginBottom: 6 }}>
              <select
                value={fact.kind}
                onChange={e => updateFact(idx, { kind: e.target.value as SeedFact['kind'] })}
                style={{ width: 100 }}
              >
                {FACT_KINDS.map(k => <option key={k} value={k}>{k}</option>)}
              </select>
              <select
                value={fact.polarity || 'asserts'}
                onChange={e => updateFact(idx, { polarity: e.target.value as 'asserts' | 'negates' })}
                style={{ width: 100 }}
              >
                <option value="asserts">asserts</option>
                <option value="negates">negates</option>
              </select>
              <button className="btn-remove-sm" onClick={() => removeFact(idx)}>&#x2715;</button>
            </div>
            <textarea
              value={fact.text}
              onChange={e => updateFact(idx, { text: e.target.value })}
              rows={2}
              placeholder="Self-contained sentence, canonical phrasing."
            />
          </div>
        </div>
      ))}

      <button className="btn-add" onClick={addFact}>+ Add Fact</button>
    </CollapsibleSection>
  )
}

export default SeedFactsSection
