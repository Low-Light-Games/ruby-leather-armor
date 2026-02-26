import React from 'react';
import type { SelectedFeatParsed, FilteredFeatWithChecks } from '../hooks/useFeats';
import { PrereqList } from '../PrereqList';
import { Picker } from '../../ui/Picker';

interface FeatsSectionProps {
  selectedFeats: SelectedFeatParsed[];
  filteredFeats: FilteredFeatWithChecks[];
  search: string;
  onSearchChange: (value: string) => void;
  onAddFeat: (featId: string) => void;
  onRemoveFeat: (featId: string) => void;
}

export const FeatsSection: React.FC<FeatsSectionProps> = ({
  selectedFeats,
  filteredFeats,
  search,
  onSearchChange,
  onAddFeat,
  onRemoveFeat,
}) => {
  return (
    <div className="picker-section">
      {/* Selected feats */}
      {selectedFeats.length > 0 ? (
        <div className="selected-items">
          {selectedFeats.map(({ raw, choice, def: feat }) => (
            <div key={raw} className="selected-item">
              <div className="selected-item-header">
                <span className="item-name">
                  {feat.name}
                  {choice && <span className="feat-choice-label"> ({choice})</span>}
                </span>
                <span className={`item-tag cat-${feat.category}`}>{feat.category}</span>
                <button className="remove-btn" onClick={() => onRemoveFeat(raw)} title="Remove feat">&times;</button>
              </div>
              <div className="selected-item-summary">{feat.summary}</div>
            </div>
          ))}
        </div>
      ) : (
        <p className="empty-text">No feats selected.</p>
      )}

      {/* Search / add */}
      <Picker<FilteredFeatWithChecks>
        search={search}
        onSearchChange={onSearchChange}
        placeholder="Search feats…"
        items={filteredFeats}
        itemKey={f => f.feat.id}
        isDisabled={f => !f.selectable}
        onSelect={f => onAddFeat(f.feat.id)}
        renderOption={({ feat, checks, selectable }) => (
          <>
            <div className="option-header">
              {!selectable && <span className="lock-icon">🔒</span>}
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
    </div>
  );
};
