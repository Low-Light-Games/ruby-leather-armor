import React from 'react';

interface CastingNoticeProps {
  type: 'no-casting' | 'not-yet' | 'prepared-list';
  message: string;
  icon?: string;
}

const ICONS: Record<string, string> = {
  'no-casting': '🚫',
  'not-yet': '⏳',
  'prepared-list': '📖',
};

export const CastingNotice: React.FC<CastingNoticeProps> = ({ type, message, icon }) => {
  return (
    <div className={`casting-notice ${type}`}>
      <span className="notice-icon">{icon || ICONS[type]}</span>
      <span>{message}</span>
    </div>
  );
};
