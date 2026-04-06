import React from 'react';

interface CombatStatInfoIconProps {
  className?: string;
}

/**
 * Small circled “i” for glossary affordance (decorative; control keeps aria-label).
 */
export const CombatStatInfoIcon: React.FC<CombatStatInfoIconProps> = ({ className }) => (
  <svg
    className={className}
    viewBox="0 0 16 16"
    width="14"
    height="14"
    aria-hidden="true"
    focusable="false"
  >
    <circle cx="8" cy="8" r="6.25" fill="none" stroke="currentColor" strokeWidth="1.2" />
    <circle cx="8" cy="5" r="0.9" fill="currentColor" />
    <path
      d="M8 7.25v4.25"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.2"
      strokeLinecap="round"
    />
  </svg>
);
