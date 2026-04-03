import {
  createContext,
  useState,
  useMemo,
  useRef,
  useCallback,
  ReactNode,
  useContext,
} from 'react';
import type { Dispatch, SetStateAction } from 'react';
import { Sheet, AttributeType } from '../types';
import type { OwnedItem, Currency } from '../rules/pathfinder_items_types';
import type { SkillRanksMap } from '../rules/pathfinder_skill_ranks';
import { EMPTY_CURRENCY } from '../rules/pathfinder_items';
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
  currentLevel: number;
  setCurrentLevel: Dispatch<SetStateAction<number>>;
  selectedFeats: string[];
  setSelectedFeats: Dispatch<SetStateAction<string[]>>;
  selectedSpells: string[];
  setSelectedSpells: Dispatch<SetStateAction<string[]>>;
  /** Owned items (with equipped state) */
  selectedItems: OwnedItem[];
  setSelectedItems: Dispatch<SetStateAction<OwnedItem[]>>;
  /** Current currency (all denominations) */
  currentCurrency: Currency;
  setCurrentCurrency: Dispatch<SetStateAction<Currency>>;
  /** Pathfinder skill ranks (stored in `sheets.skill_ranks`). */
  skillRanks: SkillRanksMap;
  setSkillRanks: Dispatch<SetStateAction<SkillRanksMap>>;
  /** True when the editor has unsaved work (synced from sheet persistence). */
  sheetHasUnsavedChanges: boolean;
  /** SheetEditor calls this when `useSheetPersistence` pristine flag changes. */
  syncSheetPristine: (pristine: boolean) => void;
  /** Forwards to sheet persistence `setDirty` once SheetEditor has registered. */
  markSheetDirty: () => void;
  /** SheetEditor registers `setDirty` here so SkillsColumn / fields can mark dirty. */
  registerSheetDirtySource: (fn: (() => void) | null) => void;
}

const SheetsContext = createContext<SheetsContextType | undefined>(
  undefined
);

export const SheetsProvider = ({ children }: { children: ReactNode }) => {
  const sheetDirtySourceRef = useRef<(() => void) | null>(null);
  const [sheetHasUnsavedChanges, setSheetHasUnsavedChanges] = useState(false);

  const registerSheetDirtySource = useCallback((fn: (() => void) | null) => {
    sheetDirtySourceRef.current = fn;
  }, []);

  const markSheetDirty = useCallback(() => {
    sheetDirtySourceRef.current?.();
  }, []);

  const syncSheetPristine = useCallback((pristine: boolean) => {
    setSheetHasUnsavedChanges(!pristine);
  }, []);

  const [sheets, setSheets] = useState<Sheet[]>([]);
  const [sheetToEdit, setSheetToEdit] = useState<Sheet | null>(null);
  const [currentAttributes, setCurrentAttributes] = useState<AttributeValues>(DEFAULT_ATTRIBUTES);
  const [currentRace, setCurrentRace] = useState<string | null>(null);
  const [currentFlexibleBonus, setCurrentFlexibleBonus] = useState<AttributeType | null>(null);
  const [currentClass, setCurrentClass] = useState<string | null>(null);
  const [currentLevel, setCurrentLevel] = useState<number>(1);
  const [selectedFeats, setSelectedFeats] = useState<string[]>([]);
  const [selectedSpells, setSelectedSpells] = useState<string[]>([]);
  const [selectedItems, setSelectedItems] = useState<OwnedItem[]>([]);
  const [currentCurrency, setCurrentCurrency] = useState<Currency>({ ...EMPTY_CURRENCY });
  const [skillRanks, setSkillRanks] = useState<SkillRanksMap>({});

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
    currentLevel,
    setCurrentLevel,
    selectedFeats,
    setSelectedFeats,
    selectedSpells,
    setSelectedSpells,
    selectedItems,
    setSelectedItems,
    currentCurrency,
    setCurrentCurrency,
    skillRanks,
    setSkillRanks,
    sheetHasUnsavedChanges,
    syncSheetPristine,
    markSheetDirty,
    registerSheetDirtySource,
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

/** Shell UI (e.g. Navbar) that mounts on pages without SheetsProvider. */
export const useSheetsContextOptional = () => useContext(SheetsContext);
