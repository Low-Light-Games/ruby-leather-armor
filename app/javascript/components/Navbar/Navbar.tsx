import { useAuth } from '../../contexts/AuthContext'
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
        <a href="/sheets" className="nav-link">Sheets</a>
        <a href="/adventures/new" className="adventure-cta">Adventure!</a>
        <button onClick={logout} className="logout-button">Logout</button>
      </div>
    </div>
  )
}

export default Navbar
