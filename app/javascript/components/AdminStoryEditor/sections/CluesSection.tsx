import CollapsibleSection from '../components/CollapsibleSection'
import type { StoryClueData, ClientLocation, StoryNpcData, DiscoveryMethod, ClueDifficulty } from '../types'
import { DISCOVERY_METHODS, CLUE_DIFFICULTIES, emptyClue } from '../types'

interface CluesSectionProps {
  clues: StoryClueData[]
  setClues: React.Dispatch<React.SetStateAction<StoryClueData[]>>
  cluesOpen: boolean
  setCluesOpen: (open: boolean) => void
  savedLocations: ClientLocation[]
  savedNpcs: StoryNpcData[]
  savedClues: StoryClueData[]
}

const CluesSection = ({
  clues, setClues, cluesOpen, setCluesOpen,
  savedLocations, savedNpcs, savedClues,
}: CluesSectionProps) => {
  const updateClue = (idx: number, patch: Partial<StoryClueData>) => {
    setClues(prev => prev.map((c, i) => i === idx ? { ...c, ...patch } : c))
  }

  const removeClue = (idx: number) => {
    const clue = clues[idx]
    if (clue.id) {
      updateClue(idx, { _destroy: true })
    } else {
      setClues(prev => prev.filter((_, i) => i !== idx))
    }
  }

  const visibleCount = clues.filter(c => !c._destroy).length

  return (
    <CollapsibleSection
      label="Clues"
      count={visibleCount}
      open={cluesOpen}
      onToggle={() => setCluesOpen(!cluesOpen)}
      hint="Discoverable pieces of information. Link to NPCs, locations, and prerequisite clues for gated reveals."
      emptyHint='No clues yet.'
      isEmpty={visibleCount === 0}
    >
      {clues.map((clue, idx) => {
        if (clue._destroy) return null
        const isAi = clue.source === 'enricher' || clue.source === 'embellisher'
        return (
          <div key={clue.id || `clue-${idx}`} className={`nested-card ${isAi ? 'ai-sourced' : ''}`}>
            <div className="nested-card-header">
              {isAi && <span className="source-badge">{clue.source}</span>}
              <input type="text" className="inline-name" value={clue.title}
                onChange={e => updateClue(idx, { title: e.target.value })}
                placeholder="Clue title" />
              <select className="compact-select" value={clue.discovery_method}
                onChange={e => updateClue(idx, { discovery_method: e.target.value as DiscoveryMethod })}>
                {DISCOVERY_METHODS.map(m => <option key={m} value={m}>{m}</option>)}
              </select>
              <select className="compact-select" value={clue.difficulty}
                onChange={e => updateClue(idx, { difficulty: e.target.value as ClueDifficulty })}>
                {CLUE_DIFFICULTIES.map(d => <option key={d} value={d}>{d}</option>)}
              </select>
              <button className="btn-remove" onClick={() => removeClue(idx)}>&#x2715;</button>
            </div>
            <div className="nested-card-body">
              <div className="inline-row">
                <select value={clue.location_id || ''} onChange={e => updateClue(idx, { location_id: Number(e.target.value) || null })}>
                  <option value="">-- location --</option>
                  {savedLocations.map(sl => <option key={sl.id} value={sl.id}>{sl.name}</option>)}
                </select>
                <select value={clue.npc_id || ''} onChange={e => updateClue(idx, { npc_id: Number(e.target.value) || null })}>
                  <option value="">-- NPC --</option>
                  {savedNpcs.map(n => <option key={n.id} value={n.id}>{n.name}</option>)}
                </select>
              </div>
              <textarea value={clue.description} rows={2} onChange={e => updateClue(idx, { description: e.target.value })}
                placeholder="Clue description..." />
              <textarea value={clue.reveals_secret} rows={2} onChange={e => updateClue(idx, { reveals_secret: e.target.value })}
                placeholder="What secret does this reveal?..." />
              {savedClues.filter(sc => sc.id !== clue.id).length > 0 && (
                <div className="relation-picker">
                  <label className="relation-label">Prerequisite clues</label>
                  <div className="relation-chips">
                    {savedClues.filter(sc => sc.id !== clue.id).map(sc => {
                      const selected = (clue.prerequisite_clue_ids || []).includes(sc.id!)
                      return (
                        <button key={sc.id} type="button"
                          className={`relation-chip ${selected ? 'selected' : ''}`}
                          onClick={() => {
                            const ids = clue.prerequisite_clue_ids || []
                            updateClue(idx, {
                              prerequisite_clue_ids: selected
                                ? ids.filter(id => id !== sc.id)
                                : [...ids, sc.id!],
                            })
                          }}>
                          {sc.title || '(untitled)'}
                        </button>
                      )
                    })}
                  </div>
                </div>
              )}
            </div>
          </div>
        )
      })}

      <button className="btn-add" onClick={() => setClues(prev => [...prev, emptyClue()])}>
        + Add Clue
      </button>
    </CollapsibleSection>
  )
}

export default CluesSection
