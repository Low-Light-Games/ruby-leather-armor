import React from 'react';
import type { Story } from '../../types';

interface StorySidebarProps {
  story: Story;
  immediateContext: string | null;
  storySummary: string | null;
}

export const StorySidebar: React.FC<StorySidebarProps> = ({ story, immediateContext, storySummary }) => {
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
        <h3>Current Scene</h3>
        <div className="context-body">
          {immediateContext || <span className="context-placeholder">No scene details yet.</span>}
        </div>
      </div>
    </div>
  );
};
