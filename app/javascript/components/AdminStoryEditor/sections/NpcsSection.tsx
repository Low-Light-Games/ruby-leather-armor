import { useState } from 'react'
import CollapsibleSection from '../components/CollapsibleSection'
import type {
  StoryNpcData, ClientLocation, NpcRole, NpcAttitude, BestiaryEntryData,
} from '../types'
import { NPC_ROLES, NPC_ATTITUDES, emptyNpc } from '../types'
import { apiFetch } from '../../../utils/api'

interface NpcsSectionProps {
  npcs: StoryNpcData[]
  setNpcs: React.Dispatch<React.SetStateAction<StoryNpcData[]>>
  npcsOpen: boolean
  setNpcsOpen: (open: boolean) => void
  savedLocations: ClientLocation[]
  storyId?: number
}

const NpcsSection = ({
  npcs, setNpcs, npcsOpen, setNpcsOpen, savedLocations, storyId,
}: NpcsSectionProps) => {
  const [generatingFor, setGeneratingFor] = useState<number | null>(null)
  const [generationError, setGenerationError] = useState<string | null>(null)

  const updateNpc = (idx: number, patch: Partial<StoryNpcData>) => {
    setNpcs(prev => prev.map((n, i) => i === idx ? { ...n, ...patch } : n))
  }

  const updateBestiary = (idx: number, patch: Partial<BestiaryEntryData>) => {
    setNpcs(prev => prev.map((n, i) => {
      if (i !== idx || !n.bestiary_entry) return n
      return { ...n, bestiary_entry: { ...n.bestiary_entry, ...patch } }
    }))
  }

  const removeNpc = (idx: number) => {
    const npc = npcs[idx]
    if (npc.id) {
      updateNpc(idx, { _destroy: true })
    } else {
      setNpcs(prev => prev.filter((_, i) => i !== idx))
    }
  }

  const generateSheet = async (idx: number) => {
    const npc = npcs[idx]
    if (!storyId || !npc.id) {
      setGenerationError('Save the NPC before generating a stat block.')
      return
    }
    setGeneratingFor(npc.id)
    setGenerationError(null)
    try {
      const sheet: BestiaryEntryData = await apiFetch(
        `/admin/stories/${storyId}/generate_npc_sheet`,
        {
          method: 'POST',
          body: JSON.stringify({ story_npc_id: npc.id }),
        },
      )
      updateNpc(idx, { bestiary_entry: sheet })
    } catch (err: any) {
      setGenerationError(err.message || 'Generation failed')
    } finally {
      setGeneratingFor(null)
    }
  }

  const visibleCount = npcs.filter(n => !n._destroy).length

  return (
    <CollapsibleSection
      label="NPCs"
      count={visibleCount}
      open={npcsOpen}
      onToggle={() => setNpcsOpen(!npcsOpen)}
      hint="Named characters the player may encounter. Every named NPC must have a generated stat block before saving."
      emptyHint='No NPCs yet.'
      isEmpty={visibleCount === 0}
    >
      {generationError && (
        <div className="feedback-error" style={{ marginBottom: 8 }}>{generationError}</div>
      )}

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

              <BestiaryPanel
                npc={npc}
                generating={generatingFor === npc.id}
                onGenerate={() => generateSheet(idx)}
                onPatch={patch => updateBestiary(idx, patch)}
              />
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

interface BestiaryPanelProps {
  npc: StoryNpcData
  generating: boolean
  onGenerate: () => void
  onPatch: (patch: Partial<BestiaryEntryData>) => void
}

// Per-StoryNpc bestiary editor. Renders as a stat block summary +
// inline-editable fields. Generate / Regenerate routes through the
// admin endpoint; field edits live in component state until story save.
const BestiaryPanel = ({ npc, generating, onGenerate, onPatch }: BestiaryPanelProps) => {
  const sheet = npc.bestiary_entry
  const buttonLabel = sheet ? 'Regenerate sheet (AI)' : 'Generate sheet (AI)'
  const canGenerate = !!npc.id && !generating

  return (
    <details className="bestiary-panel" open={!!sheet} style={{ marginTop: 8 }}>
      <summary>
        Bestiary stat block {sheet
          ? <span style={{ color: '#666' }}>(CR {sheet.cr} {sheet.creature_type}, AC {sheet.ac}, HP {sheet.hp_formula})</span>
          : <span style={{ color: '#a00' }}>— not generated yet</span>}
      </summary>
      <div style={{ marginTop: 6 }}>
        <button onClick={onGenerate} disabled={!canGenerate}>
          {generating ? 'Generating...' : buttonLabel}
        </button>
        {!npc.id && <span style={{ marginLeft: 8, color: '#666', fontSize: '0.85em' }}>Save the NPC first to enable generation.</span>}
      </div>

      {sheet && (
        <div className="bestiary-fields" style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 6, marginTop: 8 }}>
          <NumberField label="CR"   value={sheet.cr}           onChange={v => onPatch({ cr: v })} />
          <TextField   label="Type" value={sheet.creature_type} onChange={v => onPatch({ creature_type: v })} />
          <NumberField label="STR"  value={sheet.strength}     onChange={v => onPatch({ strength: v })} />
          <NumberField label="DEX"  value={sheet.dexterity}    onChange={v => onPatch({ dexterity: v })} />
          <NumberField label="CON"  value={sheet.constitution} onChange={v => onPatch({ constitution: v })} />
          <NumberField label="INT"  value={sheet.intelligence} onChange={v => onPatch({ intelligence: v })} />
          <NumberField label="WIS"  value={sheet.wisdom}       onChange={v => onPatch({ wisdom: v })} />
          <NumberField label="CHA"  value={sheet.charisma}     onChange={v => onPatch({ charisma: v })} />
          <NumberField label="AC"   value={sheet.ac}           onChange={v => onPatch({ ac: v })} />
          <NumberField label="BAB"  value={sheet.base_attack}  onChange={v => onPatch({ base_attack: v })} />
          <NumberField label="Speed" value={sheet.speed}       onChange={v => onPatch({ speed: v })} />
          <TextField   label="HP formula" value={sheet.hp_formula} onChange={v => onPatch({ hp_formula: v })} />
        </div>
      )}
    </details>
  )
}

const NumberField = ({ label, value, onChange }: { label: string; value: number; onChange: (v: number) => void }) => (
  <label style={{ display: 'flex', flexDirection: 'column', fontSize: '0.85em' }}>
    <span style={{ color: '#666' }}>{label}</span>
    <input type="number" value={value} onChange={e => onChange(Number(e.target.value) || 0)} />
  </label>
)

const TextField = ({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) => (
  <label style={{ display: 'flex', flexDirection: 'column', fontSize: '0.85em' }}>
    <span style={{ color: '#666' }}>{label}</span>
    <input type="text" value={value} onChange={e => onChange(e.target.value)} />
  </label>
)

export default NpcsSection
