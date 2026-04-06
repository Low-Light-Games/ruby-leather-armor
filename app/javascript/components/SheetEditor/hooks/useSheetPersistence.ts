import { useState, useEffect, useCallback } from 'react';
import type { Dispatch, SetStateAction } from 'react';
import type { Sheet, AttributeType } from '../../../types';
import type { AttributeValues } from '../../../contexts/SheetsContext';
import type { OwnedItem, Currency } from '../../../rules/pathfinder_items_types';
import { csrfToken } from '../../../utils/api';
import { getCastingStyle } from '../../../rules/pathfinder_spells';
import { EMPTY_CURRENCY } from '../../../rules/pathfinder_items';
import { DEFAULT_ATTRIBUTES } from './usePointBuy';
import type { SkillRanksMap } from '../../../rules/pathfinder_skill_ranks';
import { normalizeSkillRanksMap } from '../../../rules/pathfinder_skill_ranks';
import { migrateFeatListToPooled } from '../../../rules/pathfinder_feat_pools';

/** Leaving the sheet editor (another character, adventure, etc.) with a dirty sheet. */
export const UNSAVED_SHEET_CHANGES_CONFIRM_MESSAGE =
  'You have unsaved changes on this sheet. If you continue, they will be lost unless you save first. Continue anyway?';

// ── Context setters we need from the parent ─────────────────────

interface ContextSetters {
  sheets: Sheet[];
  setSheets: Dispatch<SetStateAction<Sheet[]>>;
  sheetToEdit: Sheet | null;
  setSheetToEdit: Dispatch<SetStateAction<Sheet | null>>;
  currentAttributes: AttributeValues;
  setCurrentAttributes: Dispatch<SetStateAction<AttributeValues>>;
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
  selectedItems: OwnedItem[];
  setSelectedItems: Dispatch<SetStateAction<OwnedItem[]>>;
  currentCurrency: Currency;
  setCurrentCurrency: Dispatch<SetStateAction<Currency>>;
  skillRanks: SkillRanksMap;
  setSkillRanks: Dispatch<SetStateAction<SkillRanksMap>>;
}

export interface Feedback {
  type: 'success' | 'error';
  message: string;
}

interface UseSheetPersistenceResult {
  // Form field state
  name: string;
  setName: Dispatch<SetStateAction<string>>;
  description: string;
  setDescription: Dispatch<SetStateAction<string>>;
  currentSheetId: number | null;
  // Dirty tracking
  isPristine: boolean;
  setDirty: () => void;
  // Feedback
  feedback: Feedback | null;
  dismissFeedback: () => void;
  // Actions
  saveSheet: () => Promise<void>;
  resetToNew: () => void;
}

export function useSheetPersistence(ctx: ContextSetters): UseSheetPersistenceResult {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [currentSheetId, setCurrentSheetId] = useState<number | null>(null);
  const [isPristine, setIsPristine] = useState(true);
  const [feedback, setFeedback] = useState<Feedback | null>(null);

  const setDirty = useCallback(() => setIsPristine(false), []);
  const setPristine = useCallback(() => setIsPristine(true), []);
  const dismissFeedback = useCallback(() => setFeedback(null), []);

  // ── Load sheet when sheetToEdit changes ─────────────────────────

  useEffect(() => {
    if (ctx.sheetToEdit) {
      if (!isPristine) {
        const confirmed = window.confirm(UNSAVED_SHEET_CHANGES_CONFIRM_MESSAGE);
        if (!confirmed) {
          ctx.setSheetToEdit(null);
          return;
        }
      }
      loadSheetForEdit(ctx.sheetToEdit);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ctx.sheetToEdit]);

  const loadSheetForEdit = (sheet: Sheet) => {
    setName(sheet.name);
    setDescription(sheet.description || '');
    ctx.setCurrentAttributes({
      strength: sheet.strength,
      intelligence: sheet.intelligence,
      dexterity: sheet.dexterity,
      constitution: sheet.constitution,
      wisdom: sheet.wisdom,
      charisma: sheet.charisma,
    });
    ctx.setCurrentRace(sheet.race || null);
    ctx.setCurrentFlexibleBonus((sheet.racial_bonus_attribute as AttributeType) || null);
    ctx.setCurrentClass(sheet.character_class || null);
    ctx.setCurrentLevel(sheet.level || 1);
    ctx.setSelectedFeats(migrateFeatListToPooled(sheet.details?.feats || []));

    const style = getCastingStyle(sheet.character_class);
    if (style === 'spontaneous') {
      ctx.setSelectedSpells(sheet.details?.knownSpells || sheet.details?.spells || []);
    } else if (style === 'spellbook') {
      ctx.setSelectedSpells(sheet.details?.spellbook || sheet.details?.spells || []);
    } else {
      ctx.setSelectedSpells([]);
    }

    ctx.setSelectedItems(sheet.details?.items || []);
    ctx.setCurrentCurrency(sheet.currency || { ...EMPTY_CURRENCY });
    ctx.setSkillRanks(normalizeSkillRanksMap(sheet.skill_ranks));
    setCurrentSheetId(sheet.id);
    setPristine();
    ctx.setSheetToEdit(null);
  };

  // ── Reset to blank sheet ────────────────────────────────────────

  const resetToNew = useCallback(() => {
    if (!isPristine) {
      const confirmed = window.confirm(
        'You have unsaved changes. Are you sure you want to create a new character? Your current changes will be lost.',
      );
      if (!confirmed) return;
    }
    setDirty();
    setName('');
    setDescription('');
    ctx.setCurrentAttributes(DEFAULT_ATTRIBUTES);
    ctx.setCurrentRace(null);
    ctx.setCurrentFlexibleBonus(null);
    ctx.setCurrentClass(null);
    ctx.setCurrentLevel(1);
    ctx.setSelectedFeats([]);
    ctx.setSelectedSpells([]);
    ctx.setSelectedItems([]);
    ctx.setCurrentCurrency({ ...EMPTY_CURRENCY });
    ctx.setSkillRanks({});
    setCurrentSheetId(null);
    ctx.setSheetToEdit(null);
    setPristine();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isPristine]);

  // ── Save (create / update) ──────────────────────────────────────

  const saveSheet = useCallback(async () => {
    try {
      const isUpdate = currentSheetId !== null;
      const url = isUpdate ? `/sheets/${currentSheetId}` : '/sheets';
      const method = isUpdate ? 'PATCH' : 'POST';

      const response = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        body: JSON.stringify({
          sheet: {
            name,
            description: description.trim() || null,
            race: ctx.currentRace,
            racial_bonus_attribute: ctx.currentFlexibleBonus,
            character_class: ctx.currentClass,
            level: ctx.currentLevel,
            feat_ids: migrateFeatListToPooled(ctx.selectedFeats),
            ...(getCastingStyle(ctx.currentClass) === 'spontaneous'
              ? { known_spell_ids: ctx.selectedSpells }
              : getCastingStyle(ctx.currentClass) === 'spellbook'
              ? { spellbook_spell_ids: ctx.selectedSpells }
              : {}),
            items: ctx.selectedItems.map(i => ({
              item_id: i.itemId,
              quantity: i.quantity,
              equipped: i.equipped,
              slot_override: i.slotOverride,
            })),
            currency: ctx.currentCurrency,
            skill_ranks: ctx.skillRanks,
            ...ctx.currentAttributes,
          },
        }),
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(
          errorData.errors?.join(', ') || `HTTP error! status: ${response.status}`,
        );
      }

      const savedSheet: Sheet = await response.json();
      setFeedback({
        type: 'success',
        message: isUpdate ? 'Sheet updated successfully' : 'Sheet saved successfully',
      });

      if (isUpdate) {
        ctx.setSheets(ctx.sheets.map(s => s.id === savedSheet.id ? savedSheet : s));
      } else {
        ctx.setSheets([...ctx.sheets, savedSheet]);
      }

      setCurrentSheetId(savedSheet.id);
      setPristine();
      ctx.setSheetToEdit(savedSheet);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Error saving sheet';
      setFeedback({ type: 'error', message });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    currentSheetId, name, description,
    ctx.currentRace, ctx.currentFlexibleBonus, ctx.currentClass, ctx.currentLevel,
    ctx.selectedFeats, ctx.selectedSpells, ctx.selectedItems, ctx.currentCurrency,
    ctx.skillRanks,
    ctx.currentAttributes, ctx.sheets, resetToNew,
  ]);

  return {
    name,
    setName,
    description,
    setDescription,
    currentSheetId,
    isPristine,
    setDirty,
    feedback,
    dismissFeedback,
    saveSheet,
    resetToNew,
  };
}
