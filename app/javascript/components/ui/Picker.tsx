import React, { useId, useRef, useState } from 'react';

/**
 * Generic search-and-select dropdown used by Feats, Spells, Equipment,
 * and the adventure Spellbook editor.
 *
 * The component owns the search input and the dropdown list.
 * The consumer controls the search string, provides the filtered items,
 * and renders each option via `renderOption`.
 *
 * CSS class names follow the existing `picker-*` convention already
 * styled in SkillsColumn.scss.
 */

export interface PickerProps<T> {
  /** Current search string (controlled). */
  search: string;
  /** Called when the user types in the search box. */
  onSearchChange: (value: string) => void;
  /** Placeholder text for the search input. */
  placeholder: string;
  /** Pre-filtered list of items to show in the dropdown. */
  items: T[];
  /** Unique key for each item. */
  itemKey: (item: T) => string;
  /** Render the content of a single dropdown option. */
  renderOption: (item: T) => React.ReactNode;
  /** Called when a non-disabled item is clicked. */
  onSelect: (item: T) => void;
  /** Return true if the item should be locked (non-clickable). */
  isDisabled?: (item: T) => boolean;
  /** Optional: extra content rendered above the search input (e.g. a type-filter row). */
  before?: React.ReactNode;
  /** Optional: disable the search input itself. */
  inputDisabled?: boolean;
  /** Shown in the list when `items` is empty (still lets the user type). */
  emptyMessage?: string;
  /** Title shown in the modal header (e.g. "Feats", "Spells", "Equipment"). */
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
              onBlur={() => setTimeout(() => setIsOpen(false), 150)}
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
