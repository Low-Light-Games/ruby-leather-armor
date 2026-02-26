import { useMemo, useCallback } from 'react';
import type { Dispatch, SetStateAction } from 'react';
import type { AttributeType } from '../../../types';
import type { AttributeValues } from '../../../contexts/SheetsContext';

export const AVAILABLE_POINTS = 27;

const POINT_COSTS: Record<number, number> = {
  7: -4, 8: -2, 9: -1, 10: 0, 11: 1, 12: 2,
  13: 3, 14: 5, 15: 7, 16: 10, 17: 13, 18: 17,
};

export const DEFAULT_ATTRIBUTES: AttributeValues = {
  strength: 10,
  intelligence: 10,
  dexterity: 10,
  constitution: 10,
  wisdom: 10,
  charisma: 10,
};

interface UsePointBuyParams {
  attributes: AttributeValues;
  setAttributes: Dispatch<SetStateAction<AttributeValues>>;
  onDirty: () => void;
}

interface UsePointBuyResult {
  spentPoints: number;
  canIncrease: (attr: AttributeType) => boolean;
  canDecrease: (attr: AttributeType) => boolean;
  changeAttribute: (attr: AttributeType, op: 'increase' | 'decrease') => void;
  clearPoints: () => void;
  isDefault: boolean;
}

export function usePointBuy({
  attributes,
  setAttributes,
  onDirty,
}: UsePointBuyParams): UsePointBuyResult {
  const spentPoints = useMemo(() => {
    return Object.values(attributes).reduce((total, value) => {
      return total + (POINT_COSTS[value] || 0);
    }, 0);
  }, [attributes]);

  const canIncrease = useCallback((attribute: AttributeType): boolean => {
    const currentValue = attributes[attribute];
    if (currentValue >= 18) return false;

    const newValue = currentValue + 1;
    const currentCost = POINT_COSTS[currentValue] || 0;
    const newCost = POINT_COSTS[newValue] || 0;
    const costDifference = newCost - currentCost;

    return spentPoints + costDifference <= AVAILABLE_POINTS;
  }, [attributes, spentPoints]);

  const canDecrease = useCallback((attribute: AttributeType): boolean => {
    return attributes[attribute] > 7;
  }, [attributes]);

  const changeAttribute = useCallback((
    attribute: AttributeType,
    operation: 'increase' | 'decrease',
  ) => {
    if (operation === 'increase' && !canIncrease(attribute)) return;
    if (operation === 'decrease' && !canDecrease(attribute)) return;

    const delta = operation === 'increase' ? 1 : -1;
    onDirty();
    setAttributes(prev => ({ ...prev, [attribute]: prev[attribute] + delta }));
  }, [canIncrease, canDecrease, setAttributes, onDirty]);

  const clearPoints = useCallback(() => {
    onDirty();
    setAttributes(DEFAULT_ATTRIBUTES);
  }, [setAttributes, onDirty]);

  const isDefault = useMemo(
    () => JSON.stringify(attributes) === JSON.stringify(DEFAULT_ATTRIBUTES),
    [attributes],
  );

  return { spentPoints, canIncrease, canDecrease, changeAttribute, clearPoints, isDefault };
}
