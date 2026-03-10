import type { AdventureMessage, RollRequest } from '../../types'
import { extractRollRequests, rollLabel } from './rollHelpers'
import { ERROR_ID, THINKING_ID } from './hooks/useAdventureMessages'

interface ChatMessageProps {
  msg: AdventureMessage
  isAdmin: boolean
  onRetry: () => void
}

const ChatMessage = ({ msg, isAdmin, onRetry }: ChatMessageProps) => {
  if (msg.id === THINKING_ID) {
    return (
      <div className="chat-message msg-dm msg-thinking">
        <div className="msg-header">
          <span className="msg-role">🐉 DM</span>
        </div>
        <div className="thinking-dots">
          <span /><span /><span />
        </div>
      </div>
    )
  }

  const rollRequests = msg.message_type === 'roll_request' ? extractRollRequests(msg) : []
  const msgShowDc = msg.metadata?.show_dc !== false

  return (
    <div className={`chat-message msg-${msg.role} msg-type-${msg.message_type}`}>
      <div className="msg-header">
        <span className="msg-role">
          {msg.role === 'player' ? '🗡️ You' : msg.role === 'dm' ? '🐉 DM' : '📜 System'}
        </span>
        {isAdmin && msg.pipeline_run_id && (
          <a
            href={`/admin/ai_logs/pipelines/${msg.pipeline_run_id}`}
            className="pipeline-id-link"
            target="_blank"
            rel="noopener noreferrer"
            title="View pipeline run"
          >
            {msg.pipeline_run_id.slice(0, 8)}…
          </a>
        )}
      </div>
      <div className="msg-content">{msg.content}</div>
      {rollRequests.length > 0 && (
        <div className="roll-request-badges">
          {rollRequests.map((req, i) => (
            <div key={i} className="roll-request-badge">
              <span className="roll-badge-label">🎲 {rollLabel(req)}</span>
              {msgShowDc && req.dc != null && <span className="roll-dc">DC {req.dc}</span>}
              <span className="roll-badge-desc">{req.description}</span>
            </div>
          ))}
        </div>
      )}
      {msg.id === ERROR_ID && (
        <button className="retry-btn" onClick={onRetry}>Retry</button>
      )}
    </div>
  )
}

export default ChatMessage
