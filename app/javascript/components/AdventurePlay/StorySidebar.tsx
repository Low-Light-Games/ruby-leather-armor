import React from 'react';
import type { Story } from '../../types';

const CATEGORY_LABELS: Record<string, { label: string; className: string }> = {
  combat: { label: 'Combat', className: 'cat-combat' },
  social: { label: 'Social', className: 'cat-social' },
  traversal: { label: 'Traversal', className: 'cat-traversal' },
}

interface StorySidebarProps {
  story: Story;
  immediateContext: string | null;
  storySummary: string | null;
  currentCategory: string | null;
}

export const StorySidebar: React.FC<StorySidebarProps> = ({ story, immediateContext, storySummary, currentCategory }) => {
  const categoryInfo = currentCategory ? CATEGORY_LABELS[currentCategory] : null;

  return (
    <div className="adventure-column story-column">
      <h2>{story.title}</h2>
      <p className="story-premise">{story.preview}</p>

      <div className="context-section">
        <h3>Story So Far</h3>
        <div className="context-body">
          {storySummary || <span className="context-placeholder">The adventure has just begun...</span>}
        </div>
      </div>

      <div className="context-section">
        <div className="context-header">
          <h3>Current Scene</h3>
          {categoryInfo && (
            <span className={`category-badge ${categoryInfo.className}`}>
              {categoryInfo.label}
            </span>
          )}
        </div>
        <div className="context-body">
          {immediateContext || <span className="context-placeholder">No scene details yet.</span>}
        </div>
      </div>
    </div>
  );
};
