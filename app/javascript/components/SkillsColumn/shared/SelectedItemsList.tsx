import React from 'react';

interface SelectedItem {
  id: string;
  [key: string]: any;
}

interface SelectedItemsListProps<T extends SelectedItem> {
  items: T[];
  renderItem: (item: T, onRemove: () => void) => React.ReactNode;
  onRemove: (item: T) => void;
  emptyMessage: string;
}

export function SelectedItemsList<T extends SelectedItem>({
  items,
  renderItem,
  onRemove,
  emptyMessage,
}: SelectedItemsListProps<T>) {
  if (items.length === 0) {
    return <p className="empty-text">{emptyMessage}</p>;
  }

  return (
    <div className="selected-items">
      {items.map(item => (
        <React.Fragment key={item.id}>
          {renderItem(item, () => onRemove(item))}
        </React.Fragment>
      ))}
    </div>
  );
}
