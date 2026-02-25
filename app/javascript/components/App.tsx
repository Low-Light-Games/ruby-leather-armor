import SheetEditor from './SheetEditor'
import SheetList from './SheetList'
import SkillsColumn from './SkillsColumn'
import Login from './Login'
import Navbar from './Navbar'
import './App.scss'
import { SheetsProvider } from '../contexts/SheetsContext'
import { AuthProvider, useAuth } from '../contexts/AuthContext'

const AppContent = () => {
  const { user, loading } = useAuth();

  if (loading) {
    return <div className="app">Loading...</div>;
  }

  if (!user) {
    return <Login />;
  }

  return (
    <div className="app">
      <Navbar />
      <SheetsProvider>
        <div className="app-content">
          <div className="column-editor">
            <h1>Character Sheet</h1>
            <SheetEditor />
          </div>
          <div className="column-skills">
            <h1>Character Stats</h1>
            <SkillsColumn />
          </div>
          <div className="column-list">
            <h1>My Characters</h1>
            <SheetList />
          </div>
        </div>
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