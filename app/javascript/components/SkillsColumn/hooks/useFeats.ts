import { useState, useMemo, useCallback } from 'react';
import type { Dispatch, SetStateAction } from 'react';
import type { AttributeValues } from '../../../contexts/SheetsContext';
import type { ClassDefinition } from '../../../rules/pathfinder_classes';
import {
  getAllFeats,
  computeBAB,
  checkAllPrerequisites,
  canSelectFeat,
  computeFeatSkillBonuses,
  parseFeatEntry,
  buildFeatEntry,
} from '../../../rules/pathfinder_feats';
import type { FeatDefinition, PrerequisiteContext, PrerequisiteCheck } from '../../../rules/pathfinder_feats';

// ── Public types ──────────────────────────────────────────────────

export interface SelectedFeatParsed {
  featId: string;
  choice: string | null;
  raw: string;
  def: FeatDefinition;
}

export interface FilteredFeatWithChecks {
  feat: FeatDefinition;
  checks: PrerequisiteCheck[];
  selectable: boolean;
}

export interface FeatChoiceModalState {
  feat: FeatDefinition;
  choiceType: 'skill' | 'weapon' | 'school';
}

// ── Hook params ──────────────────────────────────────────────────

interface UseFeatsParams {
  selectedFeats: string[];
  setSelectedFeats: Dispatch<SetStateAction<string[]>>;
  finalAttributes: AttributeValues;
  currentClass: string | null;
  classDef: ClassDefinition | undefined;
  currentLevel: number;
  /** Called when feat list changes (for unsaved-sheet tracking). */
  onSheetDirty?: () => void;
}

// ── Hook result ──────────────────────────────────────────────────

interface UseFeatsResult {
  // Search state
  featSearch: string;
  setFeatSearch: (v: string) => void;

  // Actions
  addFeat: (featId: string) => void;
  removeFeat: (featId: string) => void;

  // Derived lists
  filteredFeatsWithChecks: FilteredFeatWithChecks[];
  selectedFeatsParsed: SelectedFeatParsed[];

  // Feat-granted skill bonuses (consumed by useSkills)
  featSkillBonuses: Record<string, number>;

  // Prerequisite context (exposed for debugging / display)
  prereqContext: PrerequisiteContext;

  // Choice modal state
  featChoiceModal: FeatChoiceModalState | null;
  featChoiceSearch: string;
  setFeatChoiceSearch: (v: string) => void;
  confirmFeatChoice: (choice: string) => void;
  cancelFeatChoice: () => void;
}

// ── Hook implementation ──────────────────────────────────────────

export function useFeats({
  selectedFeats,
  setSelectedFeats,
  finalAttributes,
  currentClass,
  classDef,
  currentLevel,
  onSheetDirty,
}: UseFeatsParams): UseFeatsResult {
  const [featSearch, setFeatSearch] = useState('');
  const [featChoiceModal, setFeatChoiceModal] = useState<FeatChoiceModalState | null>(null);
  const [featChoiceSearch, setFeatChoiceSearch] = useState('');

  // ── Prerequisite context ────────────────────────────────────────

  const prereqContext = useMemo((): PrerequisiteContext => {
    const bab = classDef ? computeBAB(classDef.bab, currentLevel) : 0;
    return {
      finalAttributes,
      level: currentLevel,
      classId: currentClass,
      bab,
      ownedFeatIds: new Set(selectedFeats),
    };
  }, [finalAttributes, currentLevel, currentClass, classDef, selectedFeats]);

  // ── Actions ─────────────────────────────────────────────────────

  const addFeat = useCallback((featId: string) => {
    const feat = getAllFeats().find(f => f.id === featId);
    if (!feat) return;

    if (feat.choiceType) {
      setFeatChoiceModal({ feat, choiceType: feat.choiceType });
      setFeatChoiceSearch('');
      setFeatSearch('');
      return;
    }

    setSelectedFeats(prev => {
      if (prev.includes(featId)) return prev;
      onSheetDirty?.();
      return [...prev, featId];
    });
    setFeatSearch('');
  }, [setSelectedFeats, onSheetDirty]);

  const confirmFeatChoice = useCallback((choice: string) => {
    if (!featChoiceModal) return;
    const entry = buildFeatEntry(featChoiceModal.feat.id, choice);
    setSelectedFeats(prev => {
      if (prev.includes(entry)) return prev;
      onSheetDirty?.();
      return [...prev, entry];
    });
    setFeatChoiceModal(null);
    setFeatChoiceSearch('');
  }, [featChoiceModal, setSelectedFeats, onSheetDirty]);

  const cancelFeatChoice = useCallback(() => {
    setFeatChoiceModal(null);
    setFeatChoiceSearch('');
  }, []);

  const removeFeat = useCallback(
    (featId: string) => {
      setSelectedFeats(prev => {
        const next = prev.filter(id => id !== featId);
        if (next.length !== prev.length) onSheetDirty?.();
        return next;
      });
    },
    [setSelectedFeats, onSheetDirty],
  );

  // ── Derived lists ───────────────────────────────────────────────

  const filteredFeats = useMemo(() => {
    const term = featSearch.toLowerCase().trim();
    let pool = getAllFeats().filter(f => !selectedFeats.includes(f.id));
    if (term) {
      pool = pool.filter(f => f.name.toLowerCase().includes(term) || f.category.includes(term) || f.summary.toLowerCase().includes(term));
    }
    return pool.slice(0, 20);
    // getAllFeats() is a module cache filled after fetch; length must be a dep or this
    // memo stays stuck on the first (empty) result until featSearch/selectedFeats change.
  }, [featSearch, selectedFeats, getAllFeats().length]);

  const filteredFeatsWithChecks = useMemo(() => {
    return filteredFeats.map(feat => {
      const checks = checkAllPrerequisites(feat, prereqContext);
      const selectable = canSelectFeat(checks);
      return { feat, checks, selectable };
    });
  }, [filteredFeats, prereqContext]);

  const selectedFeatsParsed = useMemo(
    () => selectedFeats.map(entry => {
      const parsed = parseFeatEntry(entry);
      const def = getAllFeats().find(f => f.id === parsed.featId);
      return { ...parsed, def };
    }).filter(e => e.def != null) as SelectedFeatParsed[],
    [selectedFeats, getAllFeats().length],
  );

  // Feat-granted skill bonuses
  const featSkillBonuses = useMemo(
    () => computeFeatSkillBonuses(selectedFeats),
    [selectedFeats],
  );

  return {
    featSearch,
    setFeatSearch,
    addFeat,
    removeFeat,
    filteredFeatsWithChecks,
    selectedFeatsParsed,
    featSkillBonuses,
    prereqContext,
    featChoiceModal,
    featChoiceSearch,
    setFeatChoiceSearch,
    confirmFeatChoice,
    cancelFeatChoice,
  };
}
