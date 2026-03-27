import { useAuth } from '../../contexts/AuthContext'
import { routes } from '../../utils/routes'
import './Navbar.scss'

export const Navbar = () => {
  const { user, logout } = useAuth()

  if (!user) return null

  return (
    <div className="app-header">
      <div className="user-info">
        <span>Logged in as: {user.email}</span>
        {user.admin && <span className="admin-badge">Admin</span>}
      </div>
      <div className="header-actions">
        <a href={routes.sheets} className="nav-link">Sheets</a>
        <a href={routes.newAdventure} className="adventure-cta">Adventure!</a>
        {user.admin && <a href="/admin/stories" className="nav-link admin-panel-link">Admin Panel</a>}
        <button onClick={logout} className="logout-button">Logout</button>
      </div>
    </div>
  )
}

export default Navbar
