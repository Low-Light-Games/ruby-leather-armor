import React from 'react';
import type { FilteredFeatWithChecks, FeatPoolBlockUi } from '../hooks/useFeats';
import type { FeatPoolId } from '../../../rules/pathfinder_feat_pools';
import { PrereqList } from '../PrereqList';
import { Picker } from '../../ui/Picker';

const POOL_BLOCK_REASON: Record<NonNullable<FilteredFeatWithChecks['blockReason']>, string> = {
  prereq: 'Prerequisites not met',
  pool_full: 'No free slots in this pool',
  wrong_category: 'Wrong feat type for this pool',
  duplicate: 'Already selected',
};

interface FeatsSectionProps {
  featPoolBlocks: FeatPoolBlockUi[];
  search: string;
  onSearchChange: (value: string) => void;
  onAddFeat: (poolId: FeatPoolId, featId: string) => void;
  onRemoveFeat: (encoded: string) => void;
}

export const FeatsSection: React.FC<FeatsSectionProps> = ({
  featPoolBlocks,
  search,
  onSearchChange,
  onAddFeat,
  onRemoveFeat,
}) => {
  const anyOver = featPoolBlocks.some(b => b.overBudget);

  return (
    <div className="picker-section feats-section">
      {anyOver && (
        <p className="feat-pools-overbudget">
          You have more feats in a pool than your level, race, or class currently allows (for example after
          lowering level or changing class). Remove feats until each pool is within its limit, or adjust level
          and class to match.
        </p>
      )}

      <div className="feat-pools-global-search">
        <label className="feat-pools-search-label" htmlFor="feat-pools-search">
          Search feats (applies to every pool below)
        </label>
        <input
          id="feat-pools-search"
          type="search"
          className="feat-pools-search-input"
          value={search}
          onChange={e => onSearchChange(e.target.value)}
          placeholder="Filter by name, category, summary…"
          autoComplete="off"
        />
      </div>

      {featPoolBlocks.map(block => (
        <FeatPoolBlock
          key={block.def.id}
          block={block}
          search={search}
          onSearchChange={onSearchChange}
          onAddFeat={onAddFeat}
          onRemoveFeat={onRemoveFeat}
        />
      ))}
    </div>
  );
};

function FeatPoolBlock({
  block,
  search,
  onSearchChange,
  onAddFeat,
  onRemoveFeat,
}: {
  block: FeatPoolBlockUi;
  search: string;
  onSearchChange: (v: string) => void;
  onAddFeat: (poolId: FeatPoolId, featId: string) => void;
  onRemoveFeat: (encoded: string) => void;
}) {
  const { def, used, overBudget, selected, filteredFeats } = block;
  const canPick = def.maxSlots > 0;
  const usageClass =
    overBudget ? 'feat-pool-usage--over' : used >= def.maxSlots && def.maxSlots > 0 ? 'feat-pool-usage--full' : '';

  return (
    <section className={`feat-pool-block${overBudget ? ' feat-pool-block--over' : ''}`} aria-labelledby={`feat-pool-h-${def.id}`}>
      <div className="feat-pool-header">
        <h3 className="feat-pool-title" id={`feat-pool-h-${def.id}`}>
          {def.title}
        </h3>
        <span className={`feat-pool-usage ${usageClass}`.trim()}>
          {used} / {def.maxSlots} {def.maxSlots === 1 ? 'slot' : 'slots'}
        </span>
      </div>
      <p className="feat-pool-explanation">{def.explanation}</p>

      {selected.length > 0 ? (
        <div className="selected-items feat-pool-selected">
          {selected.map(row => (
            <div key={row.encoded} className="selected-item">
              <div className="selected-item-header">
                <span className="item-name">
                  {row.def.name}
                  {row.choice && <span className="feat-choice-label"> ({row.choice})</span>}
                </span>
                <span className={`item-tag cat-${row.def.category}`}>{row.def.category}</span>
                <button
                  type="button"
                  className="remove-btn"
                  onClick={() => onRemoveFeat(row.encoded)}
                  title="Remove feat"
                >
                  &times;
                </button>
              </div>
              <div className="selected-item-summary">{row.def.summary}</div>
            </div>
          ))}
        </div>
      ) : (
        <p className="empty-text feat-pool-empty">No feats chosen from this pool yet.</p>
      )}

      {canPick ? (
        <Picker<FilteredFeatWithChecks>
          modalTitle={`Feats — ${def.title}`}
          search={search}
          onSearchChange={onSearchChange}
          placeholder={`Add a feat to ${def.title}…`}
          items={filteredFeats}
          itemKey={f => f.feat.id}
          isDisabled={f => !f.selectable}
          onSelect={f => onAddFeat(def.id, f.feat.id)}
          renderOption={({ feat, checks, selectable, blockReason }) => (
            <>
              <div className="option-header">
                {!selectable && <span className="lock-icon" title={blockReason ? POOL_BLOCK_REASON[blockReason] : ''}>🔒</span>}
                <span className="option-name">{feat.name}</span>
                <span className={`item-tag cat-${feat.category}`}>{feat.category}</span>
              </div>
              <div className="option-summary">{feat.summary}</div>
              {checks.length > 0 && (
                <div className="option-prereqs">
                  <PrereqList checks={checks} />
                </div>
              )}
            </>
          )}
        />
      ) : (
        <p className="feat-pool-locked">No slots in this pool for your current level, race, and class.</p>
      )}
    </section>
  );
}
