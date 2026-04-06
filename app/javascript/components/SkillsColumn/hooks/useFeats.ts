import { useState, useMemo, useCallback } from 'react';
import type { Dispatch, SetStateAction } from 'react';
import { useModal } from '../../../hooks/useModal';
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
import {
  describeFeatPools,
  encodeFeatSlot,
  featListRawEntries,
  poolAllowsFeatCategory,
  FeatMigrationUtils,
  type FeatPoolId,
} from '../../../rules/pathfinder_feat_pools';
import type { FeatPoolDefinition } from '../../../rules/pathfinder_feat_pools';

// ── Public types ──────────────────────────────────────────────────

export interface SelectedFeatParsed {
  poolId: FeatPoolId;
  /** Full stored value `pool|raw` */
  encoded: string;
  featId: string;
  choice: string | null;
  raw: string;
  def: FeatDefinition;
}

export interface FilteredFeatWithChecks {
  feat: FeatDefinition;
  checks: PrerequisiteCheck[];
  selectable: boolean;
  /** Why picker row is disabled (for tooltips / future UI). */
  blockReason?: 'prereq' | 'pool_full' | 'wrong_category' | 'duplicate';
}

export interface FeatChoiceModalState {
  feat: FeatDefinition;
  choiceType: 'skill' | 'weapon' | 'school';
  poolId: FeatPoolId;
}

export interface FeatPoolBlockUi {
  def: FeatPoolDefinition;
  used: number;
  overBudget: boolean;
  selected: SelectedFeatParsed[];
  filteredFeats: FilteredFeatWithChecks[];
}

// ── Hook params ──────────────────────────────────────────────────

interface UseFeatsParams {
  selectedFeats: string[];
  setSelectedFeats: Dispatch<SetStateAction<string[]>>;
  finalAttributes: AttributeValues;
  currentRace: string | null;
  currentClass: string | null;
  classDef: ClassDefinition | undefined;
  currentLevel: number;
  onSheetDirty?: () => void;
}

// ── Hook result ──────────────────────────────────────────────────

interface UseFeatsResult {
  featSearch: string;
  setFeatSearch: (v: string) => void;
  /** Raw feat entries (no pool prefix) for modals and downstream consumers. */
  rawFeatEntries: string[];
  /** One block per pool (for sectioned UI). */
  featPoolBlocks: FeatPoolBlockUi[];
  addFeatToPool: (poolId: FeatPoolId, featId: string) => void;
  removeFeat: (encoded: string) => void;
  selectedFeatsParsed: SelectedFeatParsed[];
  featSkillBonuses: Record<string, number>;
  prereqContext: PrerequisiteContext;
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
  currentRace,
  currentClass,
  classDef,
  currentLevel,
  onSheetDirty,
}: UseFeatsParams): UseFeatsResult {
  const [featSearch, setFeatSearch] = useState('');
  const featChoiceModal = useModal<FeatChoiceModalState>();
  const [featChoiceSearch, setFeatChoiceSearch] = useState('');

  const normalizedFeats = useMemo(
    () => FeatMigrationUtils.migrateToPooledFormat(selectedFeats),
    [selectedFeats],
  );

  const rawEntries = useMemo(() => featListRawEntries(normalizedFeats), [normalizedFeats]);

  const poolDefinitions = useMemo(
    () => describeFeatPools(currentLevel, currentRace, currentClass),
    [currentLevel, currentRace, currentClass],
  );

  const usedByPool = useMemo(() => {
    const m: Record<string, number> = {};
    for (const id of ['general', 'human_bonus', 'fighter_bonus_combat'] as const) {
      m[id] = 0;
    }
    for (const enc of normalizedFeats) {
      const { poolId } = FeatMigrationUtils.parsePooledEntry(enc);
      m[poolId] = (m[poolId] || 0) + 1;
    }
    return m as Record<FeatPoolId, number>;
  }, [normalizedFeats]);

  const prereqContext = useMemo((): PrerequisiteContext => {
    const bab = classDef ? computeBAB(classDef.bab, currentLevel) : 0;
    return {
      finalAttributes,
      level: currentLevel,
      classId: currentClass,
      bab,
      ownedFeatIds: new Set(rawEntries),
    };
  }, [finalAttributes, currentLevel, currentClass, classDef, rawEntries]);

  const addFeatToPool = useCallback(
    (poolId: FeatPoolId, featId: string) => {
      const feat = getAllFeats().find(f => f.id === featId);
      if (!feat) return;

      if (
        !FeatMigrationUtils.validatePoolAssignment(featId, poolId, {
          level: currentLevel,
          raceId: currentRace,
          classId: currentClass,
        }).ok
      ) {
        return;
      }

      const poolDef = poolDefinitions.find(p => p.id === poolId);
      if (!poolDef) return;

      const used = usedByPool[poolId];
      if (used >= poolDef.maxSlots) return;

      if (feat.choiceType) {
        featChoiceModal.open({ feat, choiceType: feat.choiceType, poolId });
        setFeatChoiceSearch('');
        setFeatSearch('');
        return;
      }

      const raw = featId;
      if (rawEntries.includes(raw)) return;

      const encoded = encodeFeatSlot(poolId, raw);
      setSelectedFeats(prev => {
        const norm = FeatMigrationUtils.migrateToPooledFormat(prev);
        if (norm.includes(encoded)) return prev;
        onSheetDirty?.();
        return [...norm, encoded];
      });
      setFeatSearch('');
    },
    [
      poolDefinitions,
      usedByPool,
      rawEntries,
      setSelectedFeats,
      onSheetDirty,
      currentLevel,
      currentRace,
      currentClass,
      featChoiceModal.open,
    ],
  );

  const confirmFeatChoice = useCallback(
    (choice: string) => {
      const modal = featChoiceModal.data;
      if (!modal) return;
      const { feat, poolId } = modal;
      const entry = buildFeatEntry(feat.id, choice);
      if (rawEntries.includes(entry)) {
        featChoiceModal.close();
        setFeatChoiceSearch('');
        return;
      }

      const poolDef = poolDefinitions.find(p => p.id === poolId);
      if (!poolDef || usedByPool[poolId] >= poolDef.maxSlots) {
        featChoiceModal.close();
        setFeatChoiceSearch('');
        return;
      }

      const encoded = encodeFeatSlot(poolId, entry);
      setSelectedFeats(prev => {
        const norm = FeatMigrationUtils.migrateToPooledFormat(prev);
        if (norm.includes(encoded)) return prev;
        onSheetDirty?.();
        return [...norm, encoded];
      });
      featChoiceModal.close();
      setFeatChoiceSearch('');
    },
    [
      featChoiceModal.data,
      featChoiceModal.close,
      rawEntries,
      poolDefinitions,
      usedByPool,
      setSelectedFeats,
      onSheetDirty,
    ],
  );

  const cancelFeatChoice = useCallback(() => {
    featChoiceModal.close();
    setFeatChoiceSearch('');
  }, [featChoiceModal.close]);

  const removeFeat = useCallback(
    (encoded: string) => {
      setSelectedFeats(prev => {
        const norm = FeatMigrationUtils.migrateToPooledFormat(prev);
        const next = norm.filter(x => x !== encoded);
        if (next.length !== norm.length) onSheetDirty?.();
        return next;
      });
    },
    [setSelectedFeats, onSheetDirty],
  );

  const selectedFeatsParsed = useMemo(
    () =>
      normalizedFeats
        .map(encoded => {
          const { poolId, rawEntry } = FeatMigrationUtils.parsePooledEntry(encoded);
          const parsed = parseFeatEntry(rawEntry);
          const def = getAllFeats().find(f => f.id === parsed.featId);
          if (!def) return null;
          return {
            poolId,
            encoded,
            featId: parsed.featId,
            choice: parsed.choice,
            raw: parsed.raw,
            def,
          } as SelectedFeatParsed;
        })
        .filter((x): x is SelectedFeatParsed => x != null),
    [normalizedFeats, getAllFeats().length],
  );

  const featSkillBonuses = useMemo(
    () => computeFeatSkillBonuses(rawEntries),
    [rawEntries],
  );

  const featPoolBlocks: FeatPoolBlockUi[] = useMemo(() => {
    const term = featSearch.toLowerCase().trim();

    return poolDefinitions.map(def => {
      const used = usedByPool[def.id];
      const overBudget = used > def.maxSlots;
      const selected = selectedFeatsParsed.filter(s => s.poolId === def.id);

      let pool = getAllFeats().filter(f => {
        if (f.choiceType) return true;
        return !rawEntries.some(r => parseFeatEntry(r).featId === f.id);
      });

      pool = pool.filter(f => poolAllowsFeatCategory(def, f.category));

      if (term) {
        pool = pool.filter(
          f =>
            f.name.toLowerCase().includes(term) ||
            f.category.includes(term) ||
            f.summary.toLowerCase().includes(term),
        );
      }

      const filteredFeats: FilteredFeatWithChecks[] = pool.slice(0, 20).map(feat => {
        const checks = checkAllPrerequisites(feat, prereqContext);
        const prereqOk = canSelectFeat(checks);
        const dup = !feat.choiceType && rawEntries.some(r => parseFeatEntry(r).featId === feat.id);
        const categoryOk = poolAllowsFeatCategory(def, feat.category);
        const poolFull = def.maxSlots > 0 && used >= def.maxSlots;
        const selectable = prereqOk && !dup && categoryOk && !poolFull && def.maxSlots > 0;

        let blockReason: FilteredFeatWithChecks['blockReason'];
        if (!selectable) {
          if (dup) blockReason = 'duplicate';
          else if (!categoryOk) blockReason = 'wrong_category';
          else if (poolFull) blockReason = 'pool_full';
          else if (!prereqOk) blockReason = 'prereq';
        }

        return { feat, checks, selectable, blockReason };
      });

      return { def, used, overBudget, selected, filteredFeats };
    });
  }, [
    poolDefinitions,
    usedByPool,
    selectedFeatsParsed,
    featSearch,
    rawEntries,
    prereqContext,
    getAllFeats().length,
  ]);

  return {
    featSearch,
    setFeatSearch,
    rawFeatEntries: rawEntries,
    featPoolBlocks,
    addFeatToPool,
    removeFeat,
    selectedFeatsParsed,
    featSkillBonuses,
    prereqContext,
    featChoiceModal: featChoiceModal.data,
    featChoiceSearch,
    setFeatChoiceSearch,
    confirmFeatChoice,
    cancelFeatChoice,
  };
}
