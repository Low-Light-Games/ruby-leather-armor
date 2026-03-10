import CollapsibleSection from '../components/CollapsibleSection'
import type { EncounterTableData, EncounterTableEntryData } from '../types'
import { emptyTable, emptyEntry } from '../types'
import type { CreatureManifestEntry } from '../../../types'

interface EncounterTablesSectionProps {
  encounterTables: EncounterTableData[]
  setEncounterTables: React.Dispatch<React.SetStateAction<EncounterTableData[]>>
  encounterTablesOpen: boolean
  setEncounterTablesOpen: (open: boolean) => void
  expandedTableIdx: number | null
  setExpandedTableIdx: (idx: number | null) => void
}

const EncounterTablesSection = ({
  encounterTables, setEncounterTables,
  encounterTablesOpen, setEncounterTablesOpen,
  expandedTableIdx, setExpandedTableIdx,
}: EncounterTablesSectionProps) => {
  const updateTable = (idx: number, patch: Partial<EncounterTableData>) => {
    setEncounterTables(prev => prev.map((t, i) => i === idx ? { ...t, ...patch } : t))
  }

  const removeTable = (idx: number) => {
    const table = encounterTables[idx]
    if (table.id) {
      updateTable(idx, { _destroy: true })
    } else {
      setEncounterTables(prev => prev.filter((_, i) => i !== idx))
    }
  }

  const addEntry = (tableIdx: number) => {
    setEncounterTables(prev => prev.map((t, i) =>
      i === tableIdx ? { ...t, encounter_table_entries: [...(t.encounter_table_entries || []), emptyEntry()] } : t
    ))
  }

  const updateEntry = (tableIdx: number, entryIdx: number, patch: Partial<EncounterTableEntryData>) => {
    setEncounterTables(prev => prev.map((t, ti) => {
      if (ti !== tableIdx) return t
      const entries = (t.encounter_table_entries || []).map((e, ei) =>
        ei === entryIdx ? { ...e, ...patch } : e
      )
      return { ...t, encounter_table_entries: entries }
    }))
  }

  const removeEntry = (tableIdx: number, entryIdx: number) => {
    setEncounterTables(prev => prev.map((t, ti) => {
      if (ti !== tableIdx) return t
      const entry = (t.encounter_table_entries || [])[entryIdx]
      if (entry?.id) {
        const entries = (t.encounter_table_entries || []).map((e, ei) =>
          ei === entryIdx ? { ...e, _destroy: true } : e
        )
        return { ...t, encounter_table_entries: entries }
      }
      return { ...t, encounter_table_entries: (t.encounter_table_entries || []).filter((_, ei) => ei !== entryIdx) }
    }))
  }

  const visibleCount = encounterTables.filter(t => !t._destroy).length

  return (
    <CollapsibleSection
      label="Encounter Tables"
      count={visibleCount}
      open={encounterTablesOpen}
      onToggle={() => setEncounterTablesOpen(!encounterTablesOpen)}
      hint="Define encounter tables for this story. Each table has a chance and frequency for random encounter checks. Entries can be fixed text or AI-powered prompts."
      emptyHint="No encounter tables. A global default will be used if available."
      isEmpty={visibleCount === 0}
    >
      {encounterTables.map((table, tableIdx) => {
        if (table._destroy) return null
        const isExpanded = expandedTableIdx === tableIdx
        const visibleEntries = (table.encounter_table_entries || []).filter(e => !e._destroy)
        return (
          <div key={table.id || `table-${tableIdx}`} className="nested-card">
            <div className="nested-card-header">
              <button className="expand-btn" onClick={() => setExpandedTableIdx(isExpanded ? null : tableIdx)}>
                {isExpanded ? '▾' : '▸'}
              </button>
              <input type="text" className="inline-name" value={table.name}
                onChange={e => updateTable(tableIdx, { name: e.target.value })}
                placeholder="Table name (e.g. Road Encounters)" />
              <span className="table-meta">
                {table.encounter_chance}% / {table.check_frequency_hours}h
              </span>
              <button className="btn-remove" onClick={() => removeTable(tableIdx)}>&#x2715;</button>
            </div>

            {isExpanded && (
              <div className="nested-card-body">
                <div className="table-config-row">
                  <div className="form-field compact">
                    <label>Chance (%)</label>
                    <input type="number" value={table.encounter_chance} min={0} max={100}
                      onChange={e => updateTable(tableIdx, { encounter_chance: Number(e.target.value) })} />
                  </div>
                  <div className="form-field compact">
                    <label>Frequency (hours)</label>
                    <input type="number" value={table.check_frequency_hours} min={1}
                      onChange={e => updateTable(tableIdx, { check_frequency_hours: Number(e.target.value) })} />
                  </div>
                </div>
                <textarea value={table.description || ''} rows={2}
                  onChange={e => updateTable(tableIdx, { description: e.target.value })}
                  placeholder="Table description (optional)..." />

                <div className="entries-section">
                  <strong>Entries ({visibleEntries.length})</strong>
                  {visibleEntries.length === 0 && <p className="empty-hint">No entries yet.</p>}
                  {(table.encounter_table_entries || []).map((entry, entryIdx) => {
                    if (entry._destroy) return null
                    return (
                      <div key={entry.id || `entry-${entryIdx}`} className="entry-card">
                        <div className="entry-header">
                          <input type="text" className="inline-name" value={entry.title}
                            onChange={e => updateEntry(tableIdx, entryIdx, { title: e.target.value })}
                            placeholder="Entry title" />
                          <div className="entry-type-toggle">
                            <button
                              className={`type-btn ${entry.entry_type === 'fixed' ? 'active' : ''}`}
                              onClick={() => updateEntry(tableIdx, entryIdx, { entry_type: 'fixed' })}>
                              Fixed
                            </button>
                            <button
                              className={`type-btn ${entry.entry_type === 'ai_prompt' ? 'active' : ''}`}
                              onClick={() => updateEntry(tableIdx, entryIdx, { entry_type: 'ai_prompt' })}>
                              AI
                            </button>
                          </div>
                          <label className="weight-label">
                            W:
                            <input type="number" className="weight-input" value={entry.weight}
                              min={1} onChange={e => updateEntry(tableIdx, entryIdx, { weight: Number(e.target.value) })} />
                          </label>
                          <button className="btn-remove-sm" onClick={() => removeEntry(tableIdx, entryIdx)}>&#x2715;</button>
                        </div>
                        <label className="entry-description-label" title="Optional. For Fixed: text shown when this entry is rolled. For AI: hint used to generate the scene. Can be left blank if the creature manifest is enough.">
                          Description (optional)
                        </label>
                        <textarea value={entry.description} rows={2}
                          onChange={e => updateEntry(tableIdx, entryIdx, { description: e.target.value })}
                          placeholder={entry.entry_type === 'fixed'
                            ? 'Fixed: text shown when this entry is rolled. Leave blank if manifest is enough.'
                            : 'AI: hint for scene generation. Leave blank for generic encounter.'} />

                        <div className="manifest-section">
                          <div className="manifest-header">
                            <strong>Creatures ({(entry.creature_manifest || []).length})</strong>
                            <button className="btn-add-sm" onClick={() => {
                              const manifest = [...(entry.creature_manifest || []), { bestiary_entry_id: null, count: 1, display_name: '' }]
                              updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                            }}>+ Creature</button>
                          </div>
                          {(entry.creature_manifest || []).map((c: CreatureManifestEntry, cIdx: number) => (
                            <div key={cIdx} className="manifest-row">
                              <input type="text" className="manifest-name" value={c.display_name}
                                placeholder="Display name" onChange={e => {
                                  const manifest = [...(entry.creature_manifest || [])]
                                  manifest[cIdx] = { ...manifest[cIdx], display_name: e.target.value }
                                  updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                                }} />
                              <input type="text" className="manifest-bestiary" value={c.bestiary_entry_id || ''}
                                placeholder="Bestiary ID" onChange={e => {
                                  const manifest = [...(entry.creature_manifest || [])]
                                  manifest[cIdx] = { ...manifest[cIdx], bestiary_entry_id: e.target.value || null }
                                  updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                                }} />
                              <label className="manifest-count">
                                x<input type="number" min={1} value={c.count}
                                  onChange={e => {
                                    const manifest = [...(entry.creature_manifest || [])]
                                    manifest[cIdx] = { ...manifest[cIdx], count: Number(e.target.value) || 1 }
                                    updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                                  }} />
                              </label>
                              <button className="btn-remove-sm" onClick={() => {
                                const manifest = (entry.creature_manifest || []).filter((_: any, i: number) => i !== cIdx)
                                updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                              }}>&#x2715;</button>
                            </div>
                          ))}
                        </div>
                      </div>
                    )
                  })}
                  <button className="btn-add-sm" onClick={() => addEntry(tableIdx)}>+ Add Entry</button>
                </div>
              </div>
            )}
          </div>
        )
      })}

      <button className="btn-add" onClick={() => setEncounterTables(prev => [...prev, emptyTable()])}>
        + Add Encounter Table
      </button>
    </CollapsibleSection>
  )
}

export default EncounterTablesSection
