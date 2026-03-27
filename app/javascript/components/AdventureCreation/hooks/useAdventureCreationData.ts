import { useState, useEffect, useRef, useCallback } from 'react'
import type { Story, Sheet, AdventureSummary } from '../../../types'
import { csrfToken } from '../../../utils/api'
import { routes } from '../../../utils/routes'

const WAIT_MESSAGES = [
  "Sculpting nightmarish creatures from clay...",
  "Convincing the universe to exist...",
  "Teaching goblins to read...",
  "Populating taverns with suspicious characters...",
  "Rolling for initiative on your behalf...",
  "Brewing mysterious potions...",
  "Arguing with a dragon about property taxes...",
  "Consulting ancient tomes of forbidden knowledge...",
  "Hiring bards to compose your theme song...",
  "Placing traps in convenient locations...",
  "Negotiating with the dungeon's landlord...",
  "Convincing mimics to hold still...",
  "Calibrating the alignment of the stars...",
  "Sharpening every sword in the kingdom...",
  "Asking the oracle for directions...",
]

export function useAdventureCreationData(user: any) {
  const [stories, setStories] = useState<Story[]>([])
  const [sheets, setSheets] = useState<Sheet[]>([])
  const [adventures, setAdventures] = useState<AdventureSummary[]>([])
  const [loadingData, setLoadingData] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [waitMessage, setWaitMessage] = useState('')
  const waitIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const startWaitMessages = useCallback(() => {
    const shuffled = [...WAIT_MESSAGES].sort(() => Math.random() - 0.5)
    let idx = 0
    setWaitMessage(shuffled[0])
    waitIntervalRef.current = setInterval(() => {
      idx = (idx + 1) % shuffled.length
      setWaitMessage(shuffled[idx])
    }, 3500)
  }, [])

  const stopWaitMessages = useCallback(() => {
    if (waitIntervalRef.current) {
      clearInterval(waitIntervalRef.current)
      waitIntervalRef.current = null
    }
    setWaitMessage('')
  }, [])

  useEffect(() => {
    if (!user) return

    Promise.all([
      fetch(routes.stories).then(r => r.json()),
      fetch(`${routes.sheets}.json`).then(r => r.json()),
      fetch(`${routes.adventures}.json`).then(r => r.json()),
    ])
      .then(([storiesData, sheetsData, adventuresData]) => {
        setStories(storiesData)
        setSheets(sheetsData)
        setAdventures(adventuresData)
        setLoadingData(false)
      })
      .catch(err => {
        console.error('Failed to load data:', err)
        setError('Failed to load data.')
        setLoadingData(false)
      })
  }, [user])

  const submitAdventure = async (storyId: number, sheetId: number, directedDm: boolean, skipWorldSanityCheck: boolean) => {
    setSubmitting(true)
    setError(null)
    startWaitMessages()

    try {
      const response = await fetch(routes.adventures, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        body: JSON.stringify({
          story_id: storyId,
          sheet_id: sheetId,
          directed_dm: directedDm,
          skip_world_sanity_check: skipWorldSanityCheck,
        }),
      })

      if (!response.ok) {
        const data = await response.json()
        throw new Error(data.error || data.errors?.join(', ') || 'Failed to create adventure')
      }

      const adventure = await response.json()
      window.location.href = routes.adventure(adventure.id)
    } catch (err) {
      stopWaitMessages()
      setError(err instanceof Error ? err.message : 'Something went wrong')
      setSubmitting(false)
    }
  }

  const deleteAdventure = async (adventureId: number) => {
    if (!window.confirm('Are you sure you want to delete this adventure? This cannot be undone.')) return

    try {
      const response = await fetch(routes.adventure(adventureId), {
        method: 'DELETE',
        headers: { 'X-CSRF-Token': csrfToken() },
      })

      if (!response.ok) throw new Error('Failed to delete adventure')

      setAdventures(prev => prev.filter(a => a.id !== adventureId))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete adventure')
    }
  }

  return {
    stories, sheets, adventures,
    loadingData, submitting, error, waitMessage,
    submitAdventure, deleteAdventure,
  }
}
