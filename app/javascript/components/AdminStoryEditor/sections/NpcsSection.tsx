import CollapsibleSection from '../components/CollapsibleSection'
import type { StoryNpcData, ClientLocation, NpcRole, NpcAttitude } from '../types'
import { NPC_ROLES, NPC_ATTITUDES, emptyNpc } from '../types'

interface NpcsSectionProps {
  npcs: StoryNpcData[]
  setNpcs: React.Dispatch<React.SetStateAction<StoryNpcData[]>>
  npcsOpen: boolean
  setNpcsOpen: (open: boolean) => void
  savedLocations: ClientLocation[]
}

const NpcsSection = ({
  npcs, setNpcs, npcsOpen, setNpcsOpen, savedLocations,
}: NpcsSectionProps) => {
  const updateNpc = (idx: number, patch: Partial<StoryNpcData>) => {
    setNpcs(prev => prev.map((n, i) => i === idx ? { ...n, ...patch } : n))
  }

  const removeNpc = (idx: number) => {
    const npc = npcs[idx]
    if (npc.id) {
      updateNpc(idx, { _destroy: true })
    } else {
      setNpcs(prev => prev.filter((_, i) => i !== idx))
    }
  }

  const visibleCount = npcs.filter(n => !n._destroy).length

  return (
    <CollapsibleSection
      label="NPCs"
      count={visibleCount}
      open={npcsOpen}
      onToggle={() => setNpcsOpen(!npcsOpen)}
      hint="Named characters the player may encounter."
      emptyHint='No NPCs yet.'
      isEmpty={visibleCount === 0}
    >
      {npcs.map((npc, idx) => {
        if (npc._destroy) return null
        return (
          <div key={npc.id || `npc-${idx}`} className="nested-card">
            <div className="nested-card-header">
              <input type="text" className="inline-name" value={npc.name}
                onChange={e => updateNpc(idx, { name: e.target.value })}
                placeholder="NPC name" />
              <select className="compact-select" value={npc.role}
                onChange={e => updateNpc(idx, { role: e.target.value as NpcRole })}>
                {NPC_ROLES.map(r => <option key={r} value={r}>{r.replace('_', ' ')}</option>)}
              </select>
              <select className="compact-select" value={npc.attitude}
                onChange={e => updateNpc(idx, { attitude: e.target.value as NpcAttitude })}>
                {NPC_ATTITUDES.map(a => <option key={a} value={a}>{a}</option>)}
              </select>
              <button className="btn-remove" onClick={() => removeNpc(idx)}>&#x2715;</button>
            </div>
            <div className="nested-card-body">
              <div className="inline-row">
                <select value={npc.location_id || ''} onChange={e => updateNpc(idx, { location_id: Number(e.target.value) || null })}>
                  <option value="">-- location --</option>
                  {savedLocations.map(sl => <option key={sl.id} value={sl.id}>{sl.name}</option>)}
                </select>
                <label className="checkbox-group">
                  <input type="checkbox" checked={npc.secret} onChange={e => updateNpc(idx, { secret: e.target.checked })} />
                  Secret
                </label>
              </div>
              <textarea value={npc.description} rows={2} onChange={e => updateNpc(idx, { description: e.target.value })}
                placeholder="Description..." />
              <textarea value={npc.knowledge} rows={2} onChange={e => updateNpc(idx, { knowledge: e.target.value })}
                placeholder="What this NPC knows..." />
            </div>
          </div>
        )
      })}

      <button className="btn-add" onClick={() => setNpcs(prev => [...prev, emptyNpc()])}>
        + Add NPC
      </button>
    </CollapsibleSection>
  )
}

export default NpcsSection
