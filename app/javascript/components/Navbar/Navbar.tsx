import { useCallback, type MouseEvent } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import { useSheetsContextOptional } from '../../contexts/SheetsContext'
import { UNSAVED_SHEET_CHANGES_CONFIRM_MESSAGE } from '../SheetEditor/hooks/useSheetPersistence'
import './Navbar.scss'

export const Navbar = () => {
  const { user, logout } = useAuth()
  const sheetsCtx = useSheetsContextOptional()
  const sheetHasUnsavedChanges = sheetsCtx?.sheetHasUnsavedChanges ?? false

  const onAdventureClick = useCallback(
    (e: MouseEvent<HTMLAnchorElement>) => {
      if (sheetHasUnsavedChanges && !window.confirm(UNSAVED_SHEET_CHANGES_CONFIRM_MESSAGE)) {
        e.preventDefault()
      }
    },
    [sheetHasUnsavedChanges],
  )

  if (!user) return null

  return (
    <>
      <div className="early-access-banner" role="status">
        Early access: features, balance, and AI behavior are still changing quickly.
      </div>

      <div className="app-header">
        <div className="user-info">
          <span>Logged in as: {user.email}</span>
          {user.admin && <span className="admin-badge">Admin</span>}
        </div>
        <div className="header-actions">
          <a href="/sheets" className="nav-link">Sheets</a>
          <a href="/plans" className="nav-link">Plans</a>
          <a href="/adventures/new" className="adventure-cta" onClick={onAdventureClick}>
            Adventure!
          </a>
          {user.admin && <a href="/admin/stories" className="nav-link admin-panel-link">Admin Panel</a>}
          <button onClick={logout} className="logout-button">Logout</button>
        </div>
      </div>
    </>
  )
}

export default Navbar
