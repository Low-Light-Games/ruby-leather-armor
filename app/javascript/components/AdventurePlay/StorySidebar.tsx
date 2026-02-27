import React from 'react';
import type { Story } from '../../types';

interface StorySidebarProps {
  story: Story;
}

export const StorySidebar: React.FC<StorySidebarProps> = ({ story }) => {
  return (
    <div className="adventure-column story-column">
      <h2>{story.title}</h2>
      <p className="story-premise">{story.preview}</p>
    </div>
  );
};
