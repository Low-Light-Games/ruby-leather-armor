import { useState, useEffect, useCallback, useRef } from 'react';
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
import type { AuthUser } from '../../../types/auth';
import { canAccessPaidAdventureOptions } from '../../../utils/planAccess';
import {
  clearSheetDraft,
  isKnownEmptySheetDraft,
  loadSheetDraft,
  saveSheetDraft,
  type SheetDraftData,
} from '../../../utils/sheetDraft';

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
  type: 'success' | 'error' | 'info';
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
  persistDraft: () => void;
}

export function useSheetPersistence(ctx: ContextSetters, user: AuthUser | null): UseSheetPersistenceResult {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [currentSheetId, setCurrentSheetId] = useState<number | null>(null);
  const [isPristine, setIsPristine] = useState(true);
  const [feedback, setFeedback] = useState<Feedback | null>(null);
  const restoredDraftRef = useRef(false);

  const setDirty = useCallback(() => setIsPristine(false), []);
  const setPristine = useCallback(() => setIsPristine(true), []);
  const dismissFeedback = useCallback(() => setFeedback(null), []);
  const hasPaidAccess = !!user && canAccessPaidAdventureOptions(user);

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
    if (user) clearSheetDraft(user.id);
  };

  const buildDraft = useCallback((): SheetDraftData => ({
    name,
    description,
    attributes: ctx.currentAttributes,
    race: ctx.currentRace,
    flexibleBonus: ctx.currentFlexibleBonus,
    characterClass: ctx.currentClass,
    level: ctx.currentLevel,
    feats: ctx.selectedFeats,
    spells: ctx.selectedSpells,
    items: ctx.selectedItems,
    currency: ctx.currentCurrency,
    skillRanks: ctx.skillRanks,
  }), [
    name,
    description,
    ctx.currentAttributes,
    ctx.currentRace,
    ctx.currentFlexibleBonus,
    ctx.currentClass,
    ctx.currentLevel,
    ctx.selectedFeats,
    ctx.selectedSpells,
    ctx.selectedItems,
    ctx.currentCurrency,
    ctx.skillRanks,
  ]);

  const buildDraftRef = useRef(buildDraft);
  buildDraftRef.current = buildDraft;

  // Free tier: persist WIP to localStorage on leave (pagehide, visibility, beforeunload).
  useEffect(() => {
    if (!user || hasPaidAccess) return;

    const uid = user.id;
    let coalescingFlush = false;

    const scheduleFlush = () => {
      if (coalescingFlush) return;
      coalescingFlush = true;
      queueMicrotask(() => {
        coalescingFlush = false;
        const draft = buildDraftRef.current();
        if (isKnownEmptySheetDraft(draft)) return;
        saveSheetDraft(uid, draft);
      });
    };

    const onVisibility = () => {
      if (document.visibilityState === 'hidden') scheduleFlush();
    };

    window.addEventListener('pagehide', scheduleFlush);
    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('beforeunload', scheduleFlush);

    return () => {
      window.removeEventListener('pagehide', scheduleFlush);
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('beforeunload', scheduleFlush);
    };
  }, [hasPaidAccess, user]);

  const persistDraft = useCallback(() => {
    if (!user || isPristine) return

    saveSheetDraft(user.id, buildDraft())
  }, [buildDraft, isPristine, user]);

  const clearDraft = useCallback(() => {
    if (!user) return

    clearSheetDraft(user.id)
  }, [user]);

  const loadDraftIntoForm = useCallback((draft: SheetDraftData, options?: { markDirty?: boolean }) => {
    setName(draft.name);
    setDescription(draft.description || '');
    ctx.setCurrentAttributes(draft.attributes);
    ctx.setCurrentRace(draft.race);
    ctx.setCurrentFlexibleBonus(draft.flexibleBonus);
    ctx.setCurrentClass(draft.characterClass);
    ctx.setCurrentLevel(draft.level || 1);
    ctx.setSelectedFeats(draft.feats || []);
    ctx.setSelectedSpells(draft.spells || []);
    ctx.setSelectedItems(draft.items || []);
    ctx.setCurrentCurrency(draft.currency || { ...EMPTY_CURRENCY });
    ctx.setSkillRanks(normalizeSkillRanksMap(draft.skillRanks));
    setCurrentSheetId(null);
    ctx.setSheetToEdit(null);
    if (options?.markDirty) setDirty();
    else setPristine();
  }, [ctx, setDirty, setPristine]);

  useEffect(() => {
    if (!user || restoredDraftRef.current || ctx.sheetToEdit || currentSheetId !== null) return

    restoredDraftRef.current = true
    const draft = loadSheetDraft(user.id)
    if (!draft) return

    clearSheetDraft(user.id)
    loadDraftIntoForm(draft, { markDirty: hasPaidAccess })

    if (hasPaidAccess) return

    setFeedback({
      type: 'info',
      message:
        'We restored your work from a previous visit. It is only kept in this browser until you save or subscribe. If you leave without making new changes, it will not be kept again.',
    })
  }, [currentSheetId, ctx.sheetToEdit, hasPaidAccess, loadDraftIntoForm, user]);

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
    clearDraft();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clearDraft, isPristine]);

  // ── Save (create / update) ──────────────────────────────────────

  const saveSheet = useCallback(async () => {
    if (!hasPaidAccess) {
      if (isPristine) return
      persistDraft();
      setFeedback({
        type: 'info',
        message: 'We kept this character as a local draft in this browser. Subscribe to save it to your account and play adventures with it.',
      });
      return;
    }

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
          errorData.errors?.join(', ') || errorData.error || `HTTP error! status: ${response.status}`,
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

      clearDraft();
      setCurrentSheetId(savedSheet.id);
      setPristine();
      ctx.setSheetToEdit(savedSheet);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Error saving sheet';
      setFeedback({ type: 'error', message });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    clearDraft,
    currentSheetId, name, description,
    ctx.currentRace, ctx.currentFlexibleBonus, ctx.currentClass, ctx.currentLevel,
    ctx.selectedFeats, ctx.selectedSpells, ctx.selectedItems, ctx.currentCurrency,
    ctx.skillRanks,
    ctx.currentAttributes, ctx.sheets, hasPaidAccess, isPristine, persistDraft, resetToNew, user,
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
    persistDraft,
  };
}
