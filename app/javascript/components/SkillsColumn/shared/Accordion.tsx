import React from 'react';

interface AccordionProps {
  title: string;
  isOpen: boolean;
  onToggle: () => void;
  children: React.ReactNode;
}

export const Accordion: React.FC<AccordionProps> = ({ title, isOpen, onToggle, children }) => {
  return (
    <div className="accordion-section">
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
