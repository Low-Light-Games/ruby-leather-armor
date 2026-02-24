import {
  createContext,
  useState,
  useMemo,
  ReactNode,
  useContext,
} from 'react';
import type { Dispatch, SetStateAction } from 'react';
import { Sheet, AttributeType } from '../types';
import { getRaceById, computeRacialModifiers } from '../rules/pathfinder_races';

export type AttributeValues = Record<AttributeType, number>;

const DEFAULT_ATTRIBUTES: AttributeValues = {
  strength: 10,
  intelligence: 10,
  dexterity: 10,
  constitution: 10,
  wisdom: 10,
  charisma: 10,
};

interface SheetsContextType {
  sheets: Sheet[];
  setSheets: Dispatch<SetStateAction<Sheet[]>>;
  sheetToEdit: Sheet | null;
  setSheetToEdit: Dispatch<SetStateAction<Sheet | null>>;
  /** Base ability scores (point-buy values, 7-18 range) */
  currentAttributes: AttributeValues;
  setCurrentAttributes: Dispatch<SetStateAction<AttributeValues>>;
  /** Final ability scores = base + racial modifiers (can go below 7) */
  finalAttributes: AttributeValues;
  /** Racial ability modifiers for the currently selected race */
  racialModifiers: AttributeValues;
  currentRace: string | null;
  setCurrentRace: Dispatch<SetStateAction<string | null>>;
  currentFlexibleBonus: AttributeType | null;
  setCurrentFlexibleBonus: Dispatch<SetStateAction<AttributeType | null>>;
  currentClass: string | null;
  setCurrentClass: Dispatch<SetStateAction<string | null>>;
}

const SheetsContext = createContext<SheetsContextType | undefined>(
  undefined
);

export const SheetsProvider = ({ children }: { children: ReactNode }) => {
  const [sheets, setSheets] = useState<Sheet[]>([]);
  const [sheetToEdit, setSheetToEdit] = useState<Sheet | null>(null);
  const [currentAttributes, setCurrentAttributes] = useState<AttributeValues>(DEFAULT_ATTRIBUTES);
  const [currentRace, setCurrentRace] = useState<string | null>(null);
  const [currentFlexibleBonus, setCurrentFlexibleBonus] = useState<AttributeType | null>(null);
  const [currentClass, setCurrentClass] = useState<string | null>(null);

  const race = useMemo(() => currentRace ? getRaceById(currentRace) : undefined, [currentRace]);

  const racialModifiers = useMemo(
    () => computeRacialModifiers(race, currentFlexibleBonus),
    [race, currentFlexibleBonus],
  );

  const finalAttributes = useMemo(() => {
    const result = { ...currentAttributes };
    for (const attr of Object.keys(result) as AttributeType[]) {
      result[attr] = result[attr] + racialModifiers[attr];
    }
    return result;
  }, [currentAttributes, racialModifiers]);

  const value: SheetsContextType = {
    sheets,
    setSheets,
    sheetToEdit,
    setSheetToEdit,
    currentAttributes,
    setCurrentAttributes,
    finalAttributes,
    racialModifiers,
    currentRace,
    setCurrentRace,
    currentFlexibleBonus,
    setCurrentFlexibleBonus,
    currentClass,
    setCurrentClass,
  };

  return (
    <SheetsContext.Provider value={value}>
      {children}
    </SheetsContext.Provider>
  );
};

export const useSheetsContext = () => {
  const ctx = useContext(SheetsContext);
  if (!ctx) {
    throw new Error('useSheetsContext must be used within a SheetsProvider');
  }
  return ctx;
};
