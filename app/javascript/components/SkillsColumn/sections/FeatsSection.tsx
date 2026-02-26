import React, { useState, useMemo } from 'react';
import type { FeatDefinition, PrerequisiteCheck } from '../../../rules/pathfinder_feats';
import { PrereqList } from '../PrereqList';

interface SelectedFeat {
  raw: string;
  choice: string | null;
  def: FeatDefinition;
}

interface FilteredFeat {
  feat: FeatDefinition;
  checks: PrerequisiteCheck[];
  selectable: boolean;
}

interface FeatsSectionProps {
  selectedFeats: SelectedFeat[];
  filteredFeats: FilteredFeat[];
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
      <div className="picker-search">
        <input
          type="text"
          placeholder="Search feats…"
          value={search}
          onChange={e => onSearchChange(e.target.value)}
          className="picker-input"
        />
        {filteredFeats.length > 0 && (
          <ul className="picker-dropdown">
            {filteredFeats.map(({ feat, checks, selectable }) => (
              <li
                key={feat.id}
                className={`picker-option ${!selectable ? 'locked' : ''}`}
                onClick={() => selectable && onAddFeat(feat.id)}
              >
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
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
};
