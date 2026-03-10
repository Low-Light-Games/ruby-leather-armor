import type { StoryLocationData, ClientLocation, ClientConnection } from './types'

export const genClientId = () => crypto.randomUUID()

export const hydrateLocations = (serverLocs: StoryLocationData[]): ClientLocation[] => {
  const locs: ClientLocation[] = serverLocs.map(loc => ({
    ...loc,
    _clientId: genClientId(),
    connections_from: (loc.connections_from || []).map(conn => ({
      ...conn,
      _toRef: '',
    })),
  }))

  const idToClientId = new Map<number, string>()
  locs.forEach(l => { if (l.id) idToClientId.set(l.id, l._clientId) })

  locs.forEach(l => {
    l.connections_from.forEach(conn => {
      if (conn.to_location_id) {
        conn._toRef = idToClientId.get(conn.to_location_id) || ''
      }
    })
  })

  return locs
}

export const rehydrateLocations = (
  serverLocs: StoryLocationData[],
  prevLocs: ClientLocation[],
): ClientLocation[] => {
  const dbIdToClientId = new Map<number, string>()
  prevLocs.forEach(l => { if (l.id) dbIdToClientId.set(l.id, l._clientId) })
  const nameToClientId = new Map<string, string>()
  prevLocs.forEach(l => { if (!l._destroy && l.name) nameToClientId.set(l.name, l._clientId) })

  const locs: ClientLocation[] = serverLocs.map(loc => ({
    ...loc,
    _clientId: (loc.id ? dbIdToClientId.get(loc.id) : null) || nameToClientId.get(loc.name) || genClientId(),
    connections_from: (loc.connections_from || []).map(conn => ({
      ...conn,
      _toRef: '',
    })),
  }))

  const newIdToClientId = new Map<number, string>()
  locs.forEach(l => { if (l.id) newIdToClientId.set(l.id, l._clientId) })

  locs.forEach(l => {
    l.connections_from.forEach(conn => {
      if (conn.to_location_id) {
        conn._toRef = newIdToClientId.get(conn.to_location_id) || ''
      }
    })
  })

  return locs
}
