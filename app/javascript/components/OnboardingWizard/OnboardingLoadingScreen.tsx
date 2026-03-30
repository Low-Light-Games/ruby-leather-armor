import { useState, useEffect, useRef } from 'react'

type CharacterType = 'rogue' | 'fighter'

const WAIT_MESSAGES: Record<CharacterType, string[]> = {
  rogue: [
    "Maren checks her lockpicks...",
    "The dungeon has been notified of your arrival.",
    "Counting torches. You have five. It won't be enough.",
    "A rogue does not knock. She listens first.",
    "The DM is composing your opening scene...",
    "Sharpening daggers and wit in equal measure.",
  ],
  fighter: [
    "Aldric buckles his scale mail...",
    "The steel is sharp. The road ahead is not.",
    "A soldier needs no preamble. The door is ahead.",
    "Tightening the shield straps. It's the small things.",
    "The DM is composing your opening scene...",
    "The dungeon has stood for centuries. It will not yield easily.",
  ],
}

const CHARACTER_NAMES: Record<CharacterType, string> = {
  rogue: 'Maren Ashwick',
  fighter: 'Aldric Vane',
}

const CHARACTER_CLASSES: Record<CharacterType, string> = {
  rogue: 'Human Rogue',
  fighter: 'Human Fighter',
}

interface Props {
  characterType: CharacterType
}

const OnboardingLoadingScreen = ({ characterType }: Props) => {
  const messages = WAIT_MESSAGES[characterType]
  const [messageIndex, setMessageIndex] = useState(0)
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  useEffect(() => {
    const shuffled = [...messages].sort(() => Math.random() - 0.5)
    let idx = 0

    intervalRef.current = setInterval(() => {
      try {
        idx = (idx + 1) % shuffled.length
        setMessageIndex(idx)
      } catch {
        if (intervalRef.current) {
          clearInterval(intervalRef.current)
          intervalRef.current = null
        }
      }
    }, 3500)

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current)
    }
  }, [characterType])

  return (
    <div className="onboarding-loading">
      <div className="onboarding-loading__character">
        <p className="onboarding-loading__name">{CHARACTER_NAMES[characterType]}</p>
        <p className="onboarding-loading__class">{CHARACTER_CLASSES[characterType]}</p>
      </div>
      <div className="onboarding-loading__rule" />
      <p className="onboarding-loading__message">
        {messages[messageIndex]}
      </p>
      <p className="onboarding-loading__hint">Preparing your adventure&hellip;</p>
    </div>
  )
}

export default OnboardingLoadingScreen
