import { useEffect, useState } from 'react'
import './FlashMessage.scss'

interface FlashMessageProps {
  type: 'success' | 'error' | 'info'
  message: string
  /** Auto-dismiss after this many ms. 0 = no auto-dismiss. Default: 4000 */
  duration?: number
  onDismiss?: () => void
}

export const FlashMessage = ({ type, message, duration = 4000, onDismiss }: FlashMessageProps) => {
  const [visible, setVisible] = useState(true)
  const [fading, setFading] = useState(false)
  const persist = duration === 0

  const dismiss = () => {
    setVisible(false)
    onDismiss?.()
  }

  useEffect(() => {
    setVisible(true)
    setFading(false)

    if (duration > 0) {
      const fadeTimer = setTimeout(() => setFading(true), duration - 300)
      const hideTimer = setTimeout(() => {
        setVisible(false)
        onDismiss?.()
      }, duration)

      return () => {
        clearTimeout(fadeTimer)
        clearTimeout(hideTimer)
      }
    }
  }, [message, type, duration, onDismiss])

  if (!visible) return null

  return (
    <div
      className={`flash-toast flash-toast--${type} ${persist ? 'flash-toast--persistent' : ''} ${fading ? 'flash-toast--fading' : ''}`}
      role="alert"
      {...(persist ? {} : { onClick: dismiss })}
    >
      <span className="flash-toast__icon">
        {type === 'success' ? '✓' : type === 'error' ? '✕' : 'i'}
      </span>
      <span className="flash-toast__message">{message}</span>
      {persist && (
        <button type="button" className="flash-toast__dismiss" aria-label="Dismiss notification" onClick={dismiss}>
          ×
        </button>
      )}
    </div>
  )
}

export default FlashMessage
