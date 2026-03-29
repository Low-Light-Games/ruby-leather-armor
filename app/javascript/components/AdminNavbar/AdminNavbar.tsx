import { useAuth } from '../../contexts/AuthContext'
import { routes } from '../../utils/routes'
import './AdminNavbar.scss'

interface AdminNavbarProps {
  active?: 'stories' | 'dm_logs' | 'ai_logs' | 'dm_config'
}

export const AdminNavbar = ({ active }: AdminNavbarProps) => {
  const { user, logout } = useAuth()

  if (!user) return null

  return (
    <nav className="admin-navbar">
      <div className="navbar-left">
        <span className="user-info">Logged in as: {user.email}</span>
        <span className="admin-badge">Admin</span>
      </div>
      <div className="navbar-right">
        <a href={routes.newAdventure} className="nav-link player-view-link">Player View</a>
        <a href={`${routes.mainUrl}/admin/stories`} className={`nav-link${active === 'stories' ? ' active-link' : ''}`}>Stories</a>
        <a href={`${routes.mainUrl}/admin/dm_logs`} className={`nav-link${active === 'dm_logs' ? ' active-link' : ''}`}>DM Logs</a>
        <a href={`${routes.mainUrl}/admin/ai_logs`} className={`nav-link${active === 'ai_logs' ? ' active-link' : ''}`}>AI Logs</a>
        <a href={`${routes.mainUrl}/admin/dm_config`} className={`nav-link${active === 'dm_config' ? ' active-link' : ''}`}>DM Config</a>
        <button onClick={logout} className="logout-link">Logout</button>
      </div>
    </nav>
  )
}

export default AdminNavbar
