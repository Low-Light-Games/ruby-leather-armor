import type { AdventureSummary } from '../../types'
import { formatCurrency } from '../../rules/pathfinder_items'
import type { Currency } from '../../rules/pathfinder_items_types'
import { routes } from '../../utils/routes'

interface AdventureListProps {
  adventures: AdventureSummary[]
  loading: boolean
  onDelete: (adventureId: number) => void
}

const formatDate = (dateStr: string) => {
  const date = new Date(dateStr)
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
    + ' ' + date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
}

const AdventureList = ({ adventures, loading, onDelete }: AdventureListProps) => (
  <div className="ongoing-adventures">
    <h1>Your Adventures</h1>
    {loading ? (
      <p>Loading...</p>
    ) : adventures.length === 0 ? (
      <p className="no-adventures">No adventures yet. Start one!</p>
    ) : (
      <ul className="adventure-list">
        {adventures.map(adv => (
          <li key={adv.id} className="adventure-list-item">
            <a href={routes.adventure(adv.id)} className="adventure-link">
              <span className="adventure-character">{adv.character_name}</span>
              <span className="adventure-story">{adv.story_title}</span>
              <span className="adventure-meta">
                <span className="adventure-gold">{formatCurrency(adv.character_currency as Currency)}</span>
                <span className="adventure-date">Last played: {formatDate(adv.updated_at)}</span>
              </span>
            </a>
            <button
              className="adventure-delete"
              type="button"
              onClick={() => onDelete(adv.id)}
              title="Delete adventure"
            >
              &times;
            </button>
          </li>
        ))}
      </ul>
    )}
  </div>
)

export default AdventureList
