import CollapsibleSection from '../components/CollapsibleSection'
import type { ClientLocation, ClientConnection } from '../types'
import { TERRAIN_TYPES, emptyLocation, emptyConnection } from '../types'

interface LocationsSectionProps {
  locations: ClientLocation[]
  setLocations: React.Dispatch<React.SetStateAction<ClientLocation[]>>
  locationsOpen: boolean
  setLocationsOpen: (open: boolean) => void
  expandedLocIdx: number | null
  setExpandedLocIdx: (idx: number | null) => void
  duplicateNames: Set<string>
}

const LocationsSection = ({
  locations, setLocations,
  locationsOpen, setLocationsOpen,
  expandedLocIdx, setExpandedLocIdx,
  duplicateNames,
}: LocationsSectionProps) => {
  const visibleLocations = locations.filter(l => !l._destroy)

  const updateLocation = (idx: number, patch: Partial<ClientLocation>) => {
    setLocations(prev => prev.map((l, i) => i === idx ? { ...l, ...patch } : l))
  }

  const setStartingLocation = (idx: number) => {
    setLocations(prev => prev.map((l, i) => ({ ...l, starting: i === idx })))
  }

  const removeLocation = (idx: number) => {
    setLocations(prev => {
      const loc = prev[idx]
      const removedRef = loc._clientId

      const updated = loc.id
        ? prev.map((l, i) => i === idx ? { ...l, _destroy: true } : l)
        : prev.filter((_, i) => i !== idx)

      return updated.map(l => ({
        ...l,
        connections_from: l.connections_from.map(c =>
          c._toRef === removedRef ? { ...c, _destroy: true } : c
        ),
      }))
    })
  }

  const addConnection = (locIdx: number) => {
    setLocations(prev => prev.map((l, i) =>
      i === locIdx ? { ...l, connections_from: [...l.connections_from, emptyConnection()] } : l
    ))
  }

  const updateConnection = (locIdx: number, connIdx: number, patch: Partial<ClientConnection>) => {
    setLocations(prev => prev.map((l, li) => {
      if (li !== locIdx) return l
      const conns = l.connections_from.map((c, ci) =>
        ci === connIdx ? { ...c, ...patch } : c
      )
      return { ...l, connections_from: conns }
    }))
  }

  const removeConnection = (locIdx: number, connIdx: number) => {
    setLocations(prev => prev.map((l, li) => {
      if (li !== locIdx) return l
      const conn = l.connections_from[connIdx]
      if (conn?.id) {
        const conns = l.connections_from.map((c, ci) =>
          ci === connIdx ? { ...c, _destroy: true } : c
        )
        return { ...l, connections_from: conns }
      }
      return { ...l, connections_from: l.connections_from.filter((_, ci) => ci !== connIdx) }
    }))
  }

  const incomingConnections = (loc: ClientLocation) => {
    const incoming: { fromName: string; distance_miles: number; terrain_type: string }[] = []
    locations.forEach(other => {
      if (other._destroy || other._clientId === loc._clientId) return
      other.connections_from.forEach(conn => {
        if (conn._destroy || conn._toRef !== loc._clientId) return
        incoming.push({
          fromName: other.name,
          distance_miles: conn.distance_miles,
          terrain_type: conn.terrain_type,
        })
      })
    })
    return incoming
  }

  return (
    <CollapsibleSection
      label="Locations"
      count={visibleLocations.length}
      open={locationsOpen}
      onToggle={() => setLocationsOpen(!locationsOpen)}
      hint="Define named locations for this story. Mark one as the starting location. Connect locations with distances for travel resolution."
      emptyHint="No locations yet."
      isEmpty={visibleLocations.length === 0}
    >
      {locations.map((loc, locIdx) => {
        if (loc._destroy) return null
        const isExpanded = expandedLocIdx === locIdx
        const visibleConns = loc.connections_from.filter(c => !c._destroy)
        const incoming = incomingConnections(loc)
        const isDupeName = loc.name.trim() !== '' && duplicateNames.has(loc.name.trim().toLowerCase())
        return (
          <div key={loc._clientId} className="nested-card">
            <div className="nested-card-header">
              <button className="expand-btn" onClick={() => setExpandedLocIdx(isExpanded ? null : locIdx)}>
                {isExpanded ? '▾' : '▸'}
              </button>
              <input type="text"
                className={`inline-name ${isDupeName ? 'name-duplicate' : ''}`}
                value={loc.name}
                onChange={e => updateLocation(locIdx, { name: e.target.value })}
                placeholder="Location name" />
              {isDupeName && <span className="dup-warning" title="Duplicate name">dup</span>}
              {!loc.id && <span className="unsaved-badge">new</span>}
              <label className="starting-label">
                <input type="radio" name="starting-location"
                  checked={loc.starting}
                  onChange={() => setStartingLocation(locIdx)} />
                Start
              </label>
              <button className="btn-remove" onClick={() => removeLocation(locIdx)}>&#x2715;</button>
            </div>

            {isExpanded && (
              <div className="nested-card-body">
                <textarea value={loc.description || ''} rows={2}
                  onChange={e => updateLocation(locIdx, { description: e.target.value })}
                  placeholder="Location description..." />

                <div className="connections-section">
                  <strong>Connections</strong>
                  {visibleConns.length === 0 && incoming.length === 0 && <p className="empty-hint">No connections.</p>}
                  {loc.connections_from.map((conn, connIdx) => {
                    if (conn._destroy) return null
                    return (
                      <div key={conn.id || `conn-${connIdx}`} className="connection-row">
                        <span className="conn-direction" title="Outgoing">&rarr;</span>
                        <select value={conn._toRef || ''}
                          onChange={e => updateConnection(locIdx, connIdx, { _toRef: e.target.value })}>
                          <option value="">&mdash; destination &mdash;</option>
                          {visibleLocations.filter(vl => vl._clientId !== loc._clientId).map(vl => (
                            <option key={vl._clientId} value={vl._clientId}>
                              {vl.name || '(unnamed)'}{!vl.id ? ' *' : ''}
                            </option>
                          ))}
                        </select>
                        <input type="number" className="dist-input" value={conn.distance_miles}
                          onChange={e => updateConnection(locIdx, connIdx, { distance_miles: Number(e.target.value) })}
                          min={0.1} step={0.1} />
                        <span className="unit">mi</span>
                        <select value={conn.terrain_type}
                          onChange={e => updateConnection(locIdx, connIdx, { terrain_type: e.target.value })}>
                          {TERRAIN_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
                        </select>
                        <button className="btn-remove-sm" onClick={() => removeConnection(locIdx, connIdx)}>&#x2715;</button>
                      </div>
                    )
                  })}
                  {incoming.map((inc, i) => (
                    <div key={`inc-${i}`} className="connection-row incoming">
                      <span className="conn-direction" title="Incoming (managed from the other location)">&larr;</span>
                      <span className="incoming-label">{inc.fromName || '(unnamed)'}</span>
                      <span className="dist-display">{inc.distance_miles} mi</span>
                      <span className="terrain-display">{inc.terrain_type}</span>
                    </div>
                  ))}
                  <button className="btn-add-sm" onClick={() => addConnection(locIdx)}>+ Connection</button>
                </div>
              </div>
            )}
          </div>
        )
      })}

      <button className="btn-add" onClick={() => setLocations(prev => [...prev, emptyLocation()])}>
        + Add Location
      </button>
    </CollapsibleSection>
  )
}

export default LocationsSection
