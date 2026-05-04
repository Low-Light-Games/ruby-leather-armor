import React, { useState } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { apiFetch } from '../../utils/api';
import type { Story } from '../../types';
import type { BattlefieldSnapshot } from '../../types';
import { TacticalMapRail } from './TacticalMapRail';

const CATEGORY_LABELS: Record<string, { label: string; className: string }> = {
  combat: { label: 'Combat', className: 'cat-combat' },
  social: { label: 'Social', className: 'cat-social' },
  traversal: { label: 'Traversal', className: 'cat-traversal' },
  exploration: { label: 'Exploration', className: 'cat-exploration' },
  rest: { label: 'Rest', className: 'cat-rest' },
  inventory: { label: 'Inventory', className: 'cat-inventory' },
}

interface StorySidebarProps {
  story: Story;
  adventureId: number;
  battlefield?: BattlefieldSnapshot | null;
  combatContext: Record<string, unknown> | null;
  timeContext: Record<string, unknown> | null;
  storySummary: string | null;
  sceneSummary: string | null;
  currentCategory: string | null;
  onContextUpdate: (field: string, value: Record<string, unknown>) => void;
}

const isContextActive = (ctx: Record<string, unknown> | null): boolean =>
  ctx !== null && typeof ctx === 'object' && Object.keys(ctx).length > 0;

const ContextSection: React.FC<{
  label: string;
  className: string;
  context: Record<string, unknown> | null;
  contextKey: string;
  isAdmin: boolean;
  adventureId: number;
  onContextUpdate: (field: string, value: Record<string, unknown>) => void;
}> = ({ label, className, context, contextKey, isAdmin, adventureId, onContextUpdate }) => {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const [saving, setSaving] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);

  if (!isContextActive(context)) return null;

  const handleEdit = () => {
    setDraft(JSON.stringify(context, null, 2));
    setEditError(null);
    setEditing(true);
  };

  const handleCancel = () => {
    setEditing(false);
    setEditError(null);
  };

  const handleSave = async () => {
    setSaving(true);
    setEditError(null);
    try {
      const result = await apiFetch(`/admin/adventures/${adventureId}`, {
        method: 'PATCH',
        body: JSON.stringify({ context_field: contextKey, context_value: draft }),
      });
      onContextUpdate(contextKey, result.context_value);
      setEditing(false);
    } catch (err) {
      setEditError(err instanceof Error ? err.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="context-section context-debug-section">
      <div className="context-header">
        <h4>{label}</h4>
        <div className="context-header-actions">
          <span className={`category-badge ${className}`}>{label}</span>
          {isAdmin && !editing && (
            <button className="context-edit-btn" onClick={handleEdit}>Edit</button>
          )}
        </div>
      </div>
      {editing ? (
        <div className="context-edit-panel">
          <textarea
            className="context-json-editor"
            value={draft}
            onChange={e => setDraft(e.target.value)}
            rows={8}
          />
          {editError && <div className="context-edit-error">{editError}</div>}
          <div className="context-edit-actions">
            <button className="context-save-btn" onClick={handleSave} disabled={saving}>
              {saving ? 'Saving…' : 'Save'}
            </button>
            <button className="context-cancel-btn" onClick={handleCancel} disabled={saving}>
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <div className="context-body context-detail-list">
          {Object.entries(context!).map(([key, value]) => (
            <div key={key} className="context-entry">
              <span className="context-key">{key.replace(/_/g, ' ')}</span>
              <span className="context-value">{formatContextValue(value)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

function formatContextValue(value: unknown): string {
  if (value === null || value === undefined) return '—';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'string') return value;
  if (typeof value === 'number') return String(value);
  if (Array.isArray(value)) {
    if (value.length === 0) return '—';
    return value.map((v) =>
      typeof v === 'object' ? JSON.stringify(v) : String(v)
    ).join(', ');
  }
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function formatGameHour(timeContext: Record<string, unknown> | null): string {
  if (!timeContext) return '—';
  const raw = timeContext['current_hour'];
  if (raw === null || raw === undefined) return '—';
  const hour = typeof raw === 'number' ? raw : Number(raw);
  if (isNaN(hour)) return '—';
  const day = typeof timeContext['adventure_day'] === 'number' ? timeContext['adventure_day'] : Number(timeContext['adventure_day'] ?? 1);
  const h = Math.floor(hour) % 24;
  const m = Math.round((hour % 1) * 60);
  const period = h < 12 ? 'AM' : 'PM';
  const displayH = h % 12 === 0 ? 12 : h % 12;
  const displayM = m > 0 ? `:${String(m).padStart(2, '0')}` : '';
  return `Day ${isNaN(day) ? 1 : day} — ${displayH}${displayM} ${period}`;
}

export const StorySidebar: React.FC<StorySidebarProps> = ({
  story,
  adventureId,
  battlefield,
  combatContext,
  timeContext,
  storySummary,
  sceneSummary,
  currentCategory,
  onContextUpdate,
}) => {
  const { user } = useAuth();
  const isAdmin = user?.admin ?? false;
  const [debugOpen, setDebugOpen] = useState(false);

  const categoryInfo = currentCategory ? CATEGORY_LABELS[currentCategory] : null;

  const contexts: Array<{ key: string; label: string; className: string; ctx: Record<string, unknown> | null }> = [
    { key: 'combat', label: 'Combat', className: 'cat-combat', ctx: combatContext },
  ];

  const activeContextCount = contexts.filter(c => isContextActive(c.ctx)).length;

  return (
    <div className="adventure-column story-column">
      <h2>{story.title}</h2>
      <p className="story-premise">{story.preview}</p>

      <TacticalMapRail combatContext={combatContext} battlefield={battlefield ?? null} />

      <div className="context-section">
        <div className="context-header">
          <h3>Story So Far</h3>
          {categoryInfo && (
            <span className={`category-badge ${categoryInfo.className}`}>
              {categoryInfo.label}
            </span>
          )}
        </div>
        <div className="context-body">
          {storySummary || <span className="context-placeholder">The adventure has just begun...</span>}
        </div>
      </div>

      <div className="context-section">
        <h3>Current Scene</h3>
        <div className="context-body scene-summary-body">
          {sceneSummary
            ? <span className="scene-summary">{sceneSummary}</span>
            : <span className="context-placeholder">No scene details yet.</span>
          }
        </div>
      </div>

      <div className="context-section">
        <h3>In-Game Time</h3>
        <div className="context-body">
          <span className="game-time">{formatGameHour(timeContext)}</span>
        </div>
      </div>

      {isAdmin && activeContextCount > 0 && (
        <div className="context-debug-panel">
          <button
            className="context-debug-toggle"
            onClick={() => setDebugOpen(prev => !prev)}
          >
            {debugOpen ? '▾' : '▸'} Micro Contexts ({activeContextCount})
          </button>
          {debugOpen && contexts.map(c => (
            <ContextSection
              key={c.key}
              label={c.label}
              className={c.className}
              context={c.ctx}
              contextKey={c.key}
              isAdmin={isAdmin}
              adventureId={adventureId}
              onContextUpdate={onContextUpdate}
            />
          ))}
        </div>
      )}
    </div>
  );
};
