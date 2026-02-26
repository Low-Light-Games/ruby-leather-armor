import React from 'react';

export interface AccordionProps {
  title: string;
  isOpen: boolean;
  onToggle: () => void;
  children: React.ReactNode;
  /** Optional extra CSS class on the wrapper (e.g. for scoped theming). */
  className?: string;
}

/**
 * Collapsible section with a toggleable header.
 *
 * Uses the `accordion-section` / `accordion-header` / `accordion-body`
 * class naming convention — consumers provide their own CSS.
 */
export const Accordion: React.FC<AccordionProps> = ({
  title,
  isOpen,
  onToggle,
  children,
  className,
}) => {
  return (
    <div className={`accordion-section${className ? ` ${className}` : ''}`}>
      <button className={`accordion-header ${isOpen ? 'open' : ''}`} onClick={onToggle}>
        <span className="accordion-icon">{isOpen ? '▼' : '▶'}</span>
        {title}
      </button>
      {isOpen && (
        <div className="accordion-body">
          {children}
        </div>
      )}
    </div>
  );
};
