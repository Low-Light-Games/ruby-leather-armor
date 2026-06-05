import { useState, useCallback, type MouseEvent } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import { useSheetsContextOptional } from '../../contexts/SheetsContext'
import { UNSAVED_SHEET_CHANGES_CONFIRM_MESSAGE } from '../SheetEditor/hooks/useSheetPersistence'
import './Navbar.scss'

export const Navbar = () => {
  const { user, logout } = useAuth()
  const sheetsCtx = useSheetsContextOptional()
  const sheetHasUnsavedChanges = sheetsCtx?.sheetHasUnsavedChanges ?? false
  const graceEndsAt = user?.usage.grace_period_ends_at
    ? new Date(user.usage.grace_period_ends_at).toLocaleString()
    : null
  const [menuOpen, setMenuOpen] = useState(false)

  const onAdventureClick = useCallback(
    (e: MouseEvent<HTMLAnchorElement>) => {
      if (sheetHasUnsavedChanges && !window.confirm(UNSAVED_SHEET_CHANGES_CONFIRM_MESSAGE)) {
        e.preventDefault()
      }
    },
    [sheetHasUnsavedChanges],
  )

  if (!user) return null
  const plansCtaLabel = user.has_billing_profile ? 'Manage subscription' : 'Subscribe!'

  return (
    <>
      <div className="early-access-banner" role="status">
        Early access: features, balance, and AI behavior are still changing quickly.
      </div>
      {user.usage.delinquent && (
        <div className="billing-delinquent-banner" role="alert">
          Payment issue detected. Your grace period ends {graceEndsAt || 'soon'}.
          <a href="/plans"> Fix billing</a>.
        </div>
      )}

      <div className="app-header">
        <div className="user-info">
          <span>Logged in as: {user.email}</span>
          {user.admin && <span className="admin-badge">Admin</span>}
          <a href="/plans" className="plans-cta">
            {plansCtaLabel}
          </a>
        </div>
        <div className="header-actions">
          <a href="/sheets" className="nav-link">Sheets</a>
          <a href="/adventures/new" className="adventure-cta" onClick={onAdventureClick}>
            Adventure!
          </a>
          {user.admin && <a href="/admin/stories" className="nav-link admin-panel-link">Admin Panel</a>}
          <button onClick={logout} className="logout-button">Logout</button>
        </div>

        {/* Mobile-only hamburger button */}
        <button
          className="hamburger-btn"
          onClick={() => setMenuOpen(prev => !prev)}
          aria-label={menuOpen ? 'Close menu' : 'Open menu'}
          aria-expanded={menuOpen}
        >
          {menuOpen ? '✕' : '☰'}
        </button>
      </div>

      {/* Mobile nav drawer — rendered only when open */}
      {menuOpen && (
        <div className="mobile-nav-drawer" role="navigation" aria-label="Mobile menu">
          <span className="drawer-user">{user.email}</span>
          <a href="/sheets" className="nav-link" onClick={() => setMenuOpen(false)}>Sheets</a>
          <a
            href="/adventures/new"
            className="adventure-cta"
            onClick={e => { onAdventureClick(e); setMenuOpen(false) }}
          >
            Adventure!
          </a>
          <a href="/plans" className="plans-cta" onClick={() => setMenuOpen(false)}>
            {plansCtaLabel}
          </a>
          {user.admin && (
            <a
              href="/admin/stories"
              className="nav-link admin-panel-link"
              onClick={() => setMenuOpen(false)}
            >
              Admin Panel
            </a>
          )}
          <button onClick={() => { logout(); setMenuOpen(false) }} className="logout-button">
            Logout
          </button>
        </div>
      )}
    </>
  )
}

export default Navbar
