import CollapsibleSection from '../components/CollapsibleSection'
import type { ClientLocation } from '../types'
import { emptyLocation } from '../types'

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
      return loc.id
        ? prev.map((l, i) => i === idx ? { ...l, _destroy: true } : l)
        : prev.filter((_, i) => i !== idx)
    })
  }

  return (
    <CollapsibleSection
      label="Locations"
      count={visibleLocations.length}
      open={locationsOpen}
      onToggle={() => setLocationsOpen(!locationsOpen)}
      hint="Define named locations for this story. Mark one as the starting location. Distances between locations are computed from a procedurally placed map (see Adventure.coordinate_scale and Story.world_terrain)."
      emptyHint="No locations yet."
      isEmpty={visibleLocations.length === 0}
    >
      {locations.map((loc, locIdx) => {
        if (loc._destroy) return null
        const isExpanded = expandedLocIdx === locIdx
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
