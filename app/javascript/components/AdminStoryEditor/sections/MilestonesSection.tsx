import CollapsibleSection from '../components/CollapsibleSection'
import type { StoryMilestoneData, StoryClueData } from '../types'
import { emptyMilestone } from '../types'

interface MilestonesSectionProps {
  milestones: StoryMilestoneData[]
  setMilestones: React.Dispatch<React.SetStateAction<StoryMilestoneData[]>>
  milestonesOpen: boolean
  setMilestonesOpen: (open: boolean) => void
  savedClues: StoryClueData[]
}

const MilestonesSection = ({
  milestones, setMilestones, milestonesOpen, setMilestonesOpen, savedClues,
}: MilestonesSectionProps) => {
  const updateMilestone = (idx: number, patch: Partial<StoryMilestoneData>) => {
    setMilestones(prev => prev.map((m, i) => i === idx ? { ...m, ...patch } : m))
  }

  const removeMilestone = (idx: number) => {
    const ms = milestones[idx]
    if (ms.id) {
      updateMilestone(idx, { _destroy: true })
    } else {
      setMilestones(prev => prev.filter((_, i) => i !== idx))
    }
  }

  const visibleCount = milestones.filter(m => !m._destroy).length

  return (
    <CollapsibleSection
      label="Milestones"
      count={visibleCount}
      open={milestonesOpen}
      onToggle={() => setMilestonesOpen(!milestonesOpen)}
      hint="Major plot events triggered when specific clues are discovered. Define trigger clues and consequences."
      emptyHint='No milestones yet. Use "Enrich Story" or add manually.'
      isEmpty={visibleCount === 0}
    >
      {milestones.map((ms, idx) => {
        if (ms._destroy) return null
        const isAi = ms.source === 'enricher'
        return (
          <div key={ms.id || `ms-${idx}`} className={`nested-card ${isAi ? 'ai-sourced' : ''}`}>
            <div className="nested-card-header">
              {isAi && <span className="source-badge">{ms.source}</span>}
              <input type="text" className="inline-name" value={ms.title}
                onChange={e => updateMilestone(idx, { title: e.target.value })}
                placeholder="Milestone title" />
              <button className="btn-remove" onClick={() => removeMilestone(idx)}>&#x2715;</button>
            </div>
            <div className="nested-card-body">
              <textarea value={ms.description} rows={2} onChange={e => updateMilestone(idx, { description: e.target.value })}
                placeholder="Milestone description..." />
              <textarea value={ms.consequence} rows={2} onChange={e => updateMilestone(idx, { consequence: e.target.value })}
                placeholder="What happens when this milestone is reached?..." />
              {savedClues.length > 0 && (
                <div className="relation-picker">
                  <label className="relation-label">Trigger clues</label>
                  <div className="relation-chips">
                    {savedClues.map(sc => {
                      const selected = (ms.trigger_clue_ids || []).includes(sc.id!)
                      return (
                        <button key={sc.id} type="button"
                          className={`relation-chip ${selected ? 'selected' : ''}`}
                          onClick={() => {
                            const ids = ms.trigger_clue_ids || []
                            updateMilestone(idx, {
                              trigger_clue_ids: selected
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

      <button className="btn-add" onClick={() => setMilestones(prev => [...prev, emptyMilestone()])}>
        + Add Milestone
      </button>
    </CollapsibleSection>
  )
}

export default MilestonesSection
