import { useState, useEffect, useRef } from 'react'
import { csrfToken } from '../../utils/api'
import OnboardingLoadingScreen from './OnboardingLoadingScreen'
import './OnboardingWizard.scss'

type CharacterType = 'rogue' | 'fighter'

interface CharacterData {
  type: CharacterType
  label: string
  name: string
  race: string
  characterClass: string
  alignment: string
  description: string
  str: number
  dex: number
  con: number
  int: number
  wis: number
  cha: number
  hp: number
  ac: number
  gold: number
}

const PORTRAITS: Record<CharacterType, string> = {
  rogue: '/images/onboarding/rogue-portrait.png',
  fighter: '/images/onboarding/fighter-portrait.png',
}

const CHARACTERS: CharacterData[] = [
  {
    type: 'rogue',
    label: 'The Rogue',
    name: 'Maren Ashwick',
    race: 'Human',
    characterClass: 'Rogue',
    alignment: 'Chaotic Neutral',
    description:
      'A lean, sharp-eyed woman of no particular origin and fewer allegiances. ' +
      'She learned to pick locks because doors were often between her and eating. ' +
      'She is not brave. She is practical.',
    str: 10, dex: 17, con: 12, int: 14, wis: 10, cha: 8,
    hp: 9, ac: 15, gold: 7,
  },
  {
    type: 'fighter',
    label: 'The Fighter',
    name: 'Aldric Vane',
    race: 'Human',
    characterClass: 'Fighter',
    alignment: 'Lawful Neutral',
    description:
      'A broad, quiet man who was a soldier until the company disbanded. ' +
      'He is methodical, unhurried, and does not startle easily. ' +
      'He enters dungeons because it is the trade he has left.',
    str: 17, dex: 13, con: 14, int: 10, wis: 12, cha: 8,
    hp: 12, ac: 17, gold: 4,
  },
]

interface CharacterCardProps {
  character: CharacterData
  onClick: () => void
  disabled: boolean
}

const CharacterCard = ({ character, onClick, disabled }: CharacterCardProps) => {
  const handleMouseMove = (e: React.MouseEvent<HTMLButtonElement>) => {
    const rect = e.currentTarget.getBoundingClientRect()
    e.currentTarget.style.setProperty('--ink-x', `${((e.clientX - rect.left) / rect.width) * 100}%`)
    e.currentTarget.style.setProperty('--ink-y', `${((e.clientY - rect.top) / rect.height) * 100}%`)
  }

  return (
    <button
      className="onboarding-card"
      onClick={onClick}
      onMouseMove={handleMouseMove}
      disabled={disabled}
      type="button"
    >
      <div className="onboarding-card__body">
        <div className="onboarding-card__portrait">
          <img
            src={PORTRAITS[character.type]}
            alt={`Portrait of ${character.name}`}
            width={512}
            height={640}
          />
        </div>

        <div className="onboarding-card__details">
          <h3 className="onboarding-card__name">{character.name}</h3>
          <p className="onboarding-card__meta">
            {character.label}&nbsp;&middot;&nbsp;Level 1 {character.race} {character.characterClass}&nbsp;&middot;&nbsp;{character.alignment}
          </p>
          <p className="onboarding-card__description">{character.description}</p>
          <div className="onboarding-card__abilities">
            <span>STR {character.str}</span>
            <span>DEX {character.dex}</span>
            <span>CON {character.con}</span>
            <span>INT {character.int}</span>
            <span>WIS {character.wis}</span>
            <span>CHA {character.cha}</span>
          </div>
          <p className="onboarding-card__combat">
            HP {character.hp}&nbsp;&middot;&nbsp;AC {character.ac}&nbsp;&middot;&nbsp;{character.gold}&nbsp;gp
          </p>
        </div>
      </div>

      <p className="onboarding-card__hint">— Select this adventurer —</p>
    </button>
  )
}

const OnboardingWizard = () => {
  const [submitting, setSubmitting] = useState(false)
  const [selectedType, setSelectedType] = useState<CharacterType | null>(null)
  const [error, setError] = useState<string | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  useEffect(() => {
    return () => {
      abortRef.current?.abort()
    }
  }, [])

  const handleSelect = async (characterType: CharacterType) => {
    abortRef.current?.abort()
    const controller = new AbortController()
    abortRef.current = controller

    setSelectedType(characterType)
    setSubmitting(true)
    setError(null)

    try {
      const response = await fetch('/onboarding/complete', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        body: JSON.stringify({ character_type: characterType }),
        credentials: 'same-origin',
        signal: controller.signal,
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || 'Something went wrong. Please try again.')
      }

      const redditTracker = (window as Window & { rdt?: (...args: string[]) => void }).rdt
      if (typeof redditTracker === 'function') {
        redditTracker('track', 'Lead')
      }

      // Navigate directly — AdventurePlay will re-fetch user state on mount,
      // picking up the updated onboarding_state without a flicker here.
      window.location.href = `/adventures/${data.adventure_id}`
    } catch (err) {
      if (err instanceof Error && err.name === 'AbortError') return
      setSubmitting(false)
      setSelectedType(null)
      setError(err instanceof Error ? err.message : 'Something went wrong. Please try again.')
    }
  }

  if (submitting && selectedType) {
    return <OnboardingLoadingScreen characterType={selectedType} />
  }

  return (
    <div className="onboarding-wizard">
      <div className="onboarding-wizard__intro">
        <p>
          Two adventurers have already signed the ledger. Their equipment is packed,
          their debts are paid — or at least abandoned — and they are ready to descend.
          You may take up either one as your own.
        </p>
        <p>
          Alternatively, you may draft your own adventurer in the builder. Only
          paying users can save custom characters and take them into adventures,
          so you will know the terms before you invest your time.
        </p>
      </div>

      <hr className="onboarding-wizard__rule" />

      <h2 className="onboarding-wizard__section-heading">The Signed Ledger</h2>

      {error && (
        <div className="onboarding-wizard__error">
          <p>{error}</p>
          {error.toLowerCase().includes('no adventure') && (
            <a href="/sheets?builder_notice=custom_character_paywall">Build your own character instead</a>
          )}
        </div>
      )}

      <div className="onboarding-wizard__cards">
        {CHARACTERS.map((char) => (
          <CharacterCard
            key={char.type}
            character={char}
            onClick={() => handleSelect(char.type)}
            disabled={submitting}
          />
        ))}
      </div>

      <hr className="onboarding-wizard__rule" />

      <div className="onboarding-wizard__own">
        <h2 className="onboarding-wizard__section-heading">Or, Arrive Unknown</h2>
        <p className="onboarding-wizard__own-desc">
          Sketch your own first-level character in the builder. Only subscribers
          can save custom characters and use them in adventures.
        </p>
        <a href="/sheets?builder_notice=custom_character_paywall" className="onboarding-wizard__own-link">
          Create a Character
        </a>
      </div>
    </div>
  )
}

export default OnboardingWizard
