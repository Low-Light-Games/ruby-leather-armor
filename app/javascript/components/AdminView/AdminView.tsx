import { useEffect, useState } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { Sheet } from '../../types';
import './AdminView.scss';

export const AdminView = () => {
  const { user } = useAuth();
  const [sheets, setSheets] = useState<Sheet[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (user?.admin) {
      fetchAllSheets();
    }
  }, [user]);

  const fetchAllSheets = async () => {
    try {
      setLoading(true);
      const response = await fetch('admin/all_sheets');
      if (!response.ok) {
        throw new Error('Failed to fetch sheets');
      }
      const data = await response.json();
      setSheets(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error loading sheets');
    } finally {
      setLoading(false);
    }
  };

  if (!user?.admin) {
    return <div className="admin-view">Access denied. Admin privileges required.</div>;
  }

  if (loading) {
    return <div className="admin-view">Loading all character sheets...</div>;
  }

  if (error) {
    return <div className="admin-view feedback-error">{error}</div>;
  }

  return (
    <div className="admin-view">
      <h1>Admin View - All Character Sheets</h1>
      <p className="admin-info">Total sheets: {sheets.length}</p>
      {sheets.length === 0 ? (
        <p>No character sheets found.</p>
      ) : (
        <div className="sheets-list">
          {sheets.map((sheet) => (
            <div key={sheet.id} className="sheet-item">
              <div className="sheet-header">
                <h3>{sheet.name}</h3>
                <span className="sheet-user">User ID: {sheet.user_id || 'N/A'}</span>
                <span className="sheet-date">{new Date(sheet.created_at).toLocaleDateString()}</span>
              </div>
              <div className="sheet-attributes">
                <div className="attributes-grid">
                  <div className="attribute-item">
                    <span className="attr-label">Strength</span>
                    <span className="attr-value">{sheet.strength}</span>
                  </div>
                  <div className="attribute-item">
                    <span className="attr-label">Intelligence</span>
                    <span className="attr-value">{sheet.intelligence}</span>
                  </div>
                  <div className="attribute-item">
                    <span className="attr-label">Dexterity</span>
                    <span className="attr-value">{sheet.dexterity}</span>
                  </div>
                  <div className="attribute-item">
                    <span className="attr-label">Constitution</span>
                    <span className="attr-value">{sheet.constitution}</span>
                  </div>
                  <div className="attribute-item">
                    <span className="attr-label">Wisdom</span>
                    <span className="attr-value">{sheet.wisdom}</span>
                  </div>
                  <div className="attribute-item">
                    <span className="attr-label">Charisma</span>
                    <span className="attr-value">{sheet.charisma}</span>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
