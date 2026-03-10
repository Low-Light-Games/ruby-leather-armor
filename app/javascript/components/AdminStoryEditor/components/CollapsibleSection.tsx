import type { ReactNode } from 'react'

interface CollapsibleSectionProps {
  label: string
  count?: number
  open: boolean
  onToggle: () => void
  hint?: string
  emptyHint?: string
  isEmpty?: boolean
  children: ReactNode
}

const CollapsibleSection = ({
  label, count, open, onToggle, hint, emptyHint, isEmpty, children,
}: CollapsibleSectionProps) => (
  <div className="collapsible-section">
    <button className="section-toggle" onClick={onToggle}>
      <span className="toggle-icon">{open ? '▾' : '▸'}</span>
      {label}{count !== undefined ? ` (${count})` : ''}
    </button>

    {open && (
      <div className="section-body">
        {hint && <p className="section-hint">{hint}</p>}
        {isEmpty && emptyHint && <p className="empty-hint">{emptyHint}</p>}
        {children}
      </div>
    )}
  </div>
)

export default CollapsibleSection
