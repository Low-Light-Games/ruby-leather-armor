import React from 'react'
import { Accordion } from '../../ui/Accordion'
import type { ItemDefinition } from '../../../rules/pathfinder_items_types'

export interface InventoryAccordionProps {
  isOpen: boolean
  onToggle: () => void
  allItems: { item: ItemDefinition; id: string; quantity: number; equipped: boolean }[]
  equipError: string | null
  toggleEquip: (itemId: string) => void
  equipSaving: boolean
}

const InventoryAccordion: React.FC<InventoryAccordionProps> = ({
  isOpen,
  onToggle,
  allItems,
  equipError,
  toggleEquip,
  equipSaving,
}) => (
  <Accordion title={`Inventory (${allItems.length})`} isOpen={isOpen} onToggle={onToggle}>
    <div className="inventory-list">
      {equipError && <p className="equip-error">{equipError}</p>}
      {allItems.length === 0 ? (
        <p className="empty-hint">No items.</p>
      ) : (
        allItems.map(({ item, id, quantity, equipped }) => (
          <div key={id} className={`inventory-row ${equipped ? 'is-equipped' : ''}`} title={item.summary ?? undefined}>
            <span className="inventory-name">
              {item.name}
              {quantity > 1 && <span className="inventory-qty"> x{quantity}</span>}
            </span>
            <span className="inventory-meta">
              <span className={`inventory-type type-${item.itemType}`}>{item.itemType}</span>
              <button className={`equip-toggle ${equipped ? 'equipped' : 'unequipped'}`}
                onClick={() => toggleEquip(id)} disabled={equipSaving}
                title={equipped ? 'Unequip' : 'Equip'}>
                {equipped ? 'Unequip' : 'Equip'}
              </button>
            </span>
          </div>
        ))
      )}
    </div>
  </Accordion>
)

export default InventoryAccordion
