import React from 'react';
import type { Story, StoryState } from '../../types';

interface StorySidebarProps {
  story: Story;
  storyState: StoryState;
}

export const StorySidebar: React.FC<StorySidebarProps> = ({ story, storyState }) => {
  return (
    <div className="adventure-column story-column">
      <h2>{story.title}</h2>
      <p className="story-stage">{storyState.description}</p>
    </div>
  );
};
