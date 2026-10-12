import React, { useId, useRef, useState } from 'react';

// Lets a click on an option land before the blurred input closes the list.
const CLOSE_AFTER_BLUR_MS = 150;

// The caller owns the search string and passes items already filtered by it.
export interface PickerProps<T> {
  search: string;
  onSearchChange: (value: string) => void;
  placeholder: string;
  items: T[];
  itemKey: (item: T) => string;
  renderOption: (item: T) => React.ReactNode;
  onSelect: (item: T) => void;
  isDisabled?: (item: T) => boolean;
  before?: React.ReactNode;
  inputDisabled?: boolean;
  emptyMessage?: string;
  modalTitle: string;
}

export function Picker<T>({
  search,
  onSearchChange,
  placeholder,
  items,
  itemKey,
  renderOption,
  onSelect,
  isDisabled,
  before,
  inputDisabled,
  emptyMessage = 'No results.',
  modalTitle,
}: PickerProps<T>) {
  const [isOpen, setIsOpen] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const modalTitleId = useId();

  const togglePanel = () => {
    setIsOpen(prev => {
      const next = !prev;
      if (next) {
        requestAnimationFrame(() => inputRef.current?.focus());
      }
      return next;
    });
  };

  return (
    <>
      {before}
      <div className="picker-search">
        <button type="button" className="picker-toggle" onClick={togglePanel}>
          Search
        </button>

        <div
          className={`picker-dropdown-container ${isOpen ? 'open' : ''}`}
          role="dialog"
          aria-modal="true"
          aria-labelledby={modalTitleId}
        >
          <header className="picker-dropdown-header">
            <h2 id={modalTitleId} className="picker-dropdown-title">
              {modalTitle}
            </h2>
            <button
              type="button"
              className="picker-dropdown-close"
              aria-label="Close"
              onMouseDown={e => e.preventDefault()}
              onClick={() => setIsOpen(false)}
            >
              ×
            </button>
          </header>
          <div className="picker-dropdown-body">
            <input
              ref={inputRef}
              type="text"
              placeholder={placeholder}
              value={search}
              onChange={e => {
                onSearchChange(e.target.value);
              }}
              onFocus={() => setIsOpen(true)}
              onBlur={() => setTimeout(() => setIsOpen(false), CLOSE_AFTER_BLUR_MS)}
              onKeyDown={e => {
                if (e.key === 'Escape') (e.target as HTMLElement).blur();
              }}
              className="picker-input"
              disabled={inputDisabled}
            />
            <ul className="picker-dropdown">
              {items.length === 0 ? (
                <li className="picker-dropdown-empty">
                  {emptyMessage}
                </li>
              ) : (
                items.map(item => {
                  const disabled = isDisabled?.(item) ?? false;
                  return (
                    <li
                      key={itemKey(item)}
                      className={`picker-option ${disabled ? 'locked' : ''}`}
                      onClick={() => !disabled && onSelect(item)}
                    >
                      {renderOption(item)}
                    </li>
                  );
                })
              )}
            </ul>
          </div>
        </div>
      </div>
    </>
  );
}
