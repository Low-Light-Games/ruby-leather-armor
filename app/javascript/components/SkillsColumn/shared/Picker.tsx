import React from 'react';

interface PickerItem {
  id: string;
  [key: string]: any;
}

interface PickerProps<T extends PickerItem> {
  search: string;
  onSearchChange: (value: string) => void;
  placeholder: string;
  items: T[];
  renderItem: (item: T) => React.ReactNode;
  onSelect: (item: T) => void;
  emptyMessage?: string;
}

export function Picker<T extends PickerItem>({
  search,
  onSearchChange,
  placeholder,
  items,
  renderItem,
  onSelect,
  emptyMessage = 'No results found.',
}: PickerProps<T>) {
  return (
    <div className="picker-search">
      <input
        type="text"
        placeholder={placeholder}
        value={search}
        onChange={e => onSearchChange(e.target.value)}
        className="picker-input"
      />
      {items.length > 0 ? (
        <ul className="picker-dropdown">
          {items.map(item => (
            <li
              key={item.id}
              className="picker-option"
              onClick={() => onSelect(item)}
            >
              {renderItem(item)}
            </li>
          ))}
        </ul>
      ) : search.trim() && (
        <div className="picker-empty">{emptyMessage}</div>
      )}
    </div>
  );
}
