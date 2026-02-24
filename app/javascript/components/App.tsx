import SheetEditor from './SheetEditor'
import SheetList from './SheetList'
import Login from './Login'
import AdminView from './AdminView'
import './App.scss'
import { SheetsProvider } from '../contexts/SheetsContext'
import { AuthProvider, useAuth } from '../contexts/AuthContext'

const AppContent = () => {
  const { user, loading, logout } = useAuth();

  if (loading) {
    return <div className="app">Loading...</div>;
  }

  if (!user) {
    return <Login />;
  }

  return (
    <div className="app">
      <div className="app-header">
        <div className="user-info">
          <span>Logged in as: {user.email}</span>
          {user.admin && <span className="admin-badge">Admin</span>}
        </div>
        <button onClick={logout} className="logout-button">Logout</button>
      </div>
      <SheetsProvider>
        <div className="app-content">
          <div>
            <h1>Character Sheet</h1>
            <SheetEditor />
          </div> 
          <div>
            <h1>My Characters</h1>
            <SheetList />
          </div>
        </div>
        {user.admin && (
          <div className="admin-section">
            <h1>Admin Panel</h1>
            <AdminView />
          </div>
        )}
      </SheetsProvider>
    </div>
  );
};

export const App = () => {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  );
};

export default App