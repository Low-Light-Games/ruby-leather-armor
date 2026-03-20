import React, { useState } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import type { Story } from '../../types';

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
  traversalContext: Record<string, unknown> | null;
  combatContext: Record<string, unknown> | null;
  socialContext: Record<string, unknown> | null;
  explorationContext: Record<string, unknown> | null;
  restContext: Record<string, unknown> | null;
  inventoryContext: Record<string, unknown> | null;
  timeContext: Record<string, unknown> | null;
  storySummary: string | null;
  sceneSummary: string | null;
  currentCategory: string | null;
  onUpdateContexts: (contexts: Record<string, any>) => Promise<void>;
}

const isContextActive = (ctx: Record<string, unknown> | null): boolean =>
  ctx !== null && typeof ctx === 'object' && Object.keys(ctx).length > 0;

const ContextSection: React.FC<{
  label: string;
  className: string;
  context: Record<string, unknown> | null;
  contextKey: string;
  isEditing: boolean;
  editedJson: string;
  onEdit: () => void;
  onSave: () => void;
  onCancel: () => void;
  onJsonChange: (json: string) => void;
  saving: boolean;
  error: string | null;
}> = ({ label, className, context, contextKey, isEditing, editedJson, onEdit, onSave, onCancel, onJsonChange, saving, error }) => {
  if (!isContextActive(context) && !isEditing) return null;

  return (
    <div className="context-section context-debug-section">
      <div className="context-header">
        <h4>{label}</h4>
        <span className={`category-badge ${className}`}>{label}</span>
        {isEditing ? (
          <div className="context-actions">
            <button onClick={onSave} disabled={saving} className="btn btn-small btn-primary">
              {saving ? 'Saving...' : 'Save'}
            </button>
            <button onClick={onCancel} disabled={saving} className="btn btn-small btn-secondary">
              Cancel
            </button>
          </div>
        ) : (
          <button onClick={onEdit} className="btn btn-small btn-outline">Edit</button>
        )}
      </div>
      {error && <div className="error-message">{error}</div>}
      {isEditing ? (
        <textarea
          value={editedJson}
          onChange={(e) => onJsonChange(e.target.value)}
          className="context-editor"
          rows={10}
          disabled={saving}
        />
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
  traversalContext,
  combatContext,
  socialContext,
  explorationContext,
  restContext,
  inventoryContext,
  timeContext,
  storySummary,
  sceneSummary,
  currentCategory,
  onUpdateContexts,
}) => {
  const { user } = useAuth();
  const isAdmin = user?.admin ?? false;
  const [debugOpen, setDebugOpen] = useState(false);
  const [editingContext, setEditingContext] = useState<string | null>(null);
  const [editedJson, setEditedJson] = useState<string>('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleEdit = (contextKey: string, context: Record<string, unknown> | null) => {
    setEditingContext(contextKey);
    setEditedJson(JSON.stringify(context || {}, null, 2));
    setError(null);
  };

  const handleSave = async () => {
    if (!editingContext) return;
    setSaving(true);
    setError(null);
    try {
      const parsed = JSON.parse(editedJson);
      await onUpdateContexts({ [editingContext]: parsed });
      setEditingContext(null);
      setEditedJson('');
    } catch (err) {
      setError('Invalid JSON');
    } finally {
      setSaving(false);
    }
  };

  const handleCancel = () => {
    setEditingContext(null);
    setEditedJson('');
    setError(null);
  };

  const contexts: Array<{ key: string; label: string; className: string; ctx: Record<string, unknown> | null }> = [
    { key: 'traversal', label: 'Traversal', className: 'cat-traversal', ctx: traversalContext },
    { key: 'combat', label: 'Combat', className: 'cat-combat', ctx: combatContext },
    { key: 'social', label: 'Social', className: 'cat-social', ctx: socialContext },
    { key: 'exploration', label: 'Exploration', className: 'cat-exploration', ctx: explorationContext },
    { key: 'rest', label: 'Rest', className: 'cat-rest', ctx: restContext },
    { key: 'inventory', label: 'Inventory', className: 'cat-inventory', ctx: inventoryContext },
  ];

  const activeContextCount = contexts.filter(c => isContextActive(c.ctx)).length;

  return (
    <div className="adventure-column story-column">
      <h2>{story.title}</h2>
      <p className="story-premise">{story.preview}</p>

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
              isEditing={editingContext === c.key}
              editedJson={editingContext === c.key ? editedJson : ''}
              onEdit={() => handleEdit(c.key, c.ctx)}
              onSave={handleSave}
              onCancel={handleCancel}
              onJsonChange={setEditedJson}
              saving={saving}
              error={editingContext === c.key ? error : null}
            />
          ))}
        </div>
      )}
    </div>
  );
};
