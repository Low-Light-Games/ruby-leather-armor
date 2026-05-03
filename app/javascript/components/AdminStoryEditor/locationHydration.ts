import type { StoryLocationData, ClientLocation } from './types'

export const genClientId = () => crypto.randomUUID()

export const hydrateLocations = (serverLocs: StoryLocationData[]): ClientLocation[] =>
  serverLocs.map(loc => ({ ...loc, _clientId: genClientId() }))

export const rehydrateLocations = (
  serverLocs: StoryLocationData[],
  prevLocs: ClientLocation[],
): ClientLocation[] => {
  const dbIdToClientId = new Map<number, string>()
  prevLocs.forEach(l => { if (l.id) dbIdToClientId.set(l.id, l._clientId) })
  const nameToClientId = new Map<string, string>()
  prevLocs.forEach(l => { if (!l._destroy && l.name) nameToClientId.set(l.name, l._clientId) })

  return serverLocs.map(loc => ({
    ...loc,
    _clientId:
      (loc.id ? dbIdToClientId.get(loc.id) : null) ||
      nameToClientId.get(loc.name) ||
      genClientId(),
  }))
}
