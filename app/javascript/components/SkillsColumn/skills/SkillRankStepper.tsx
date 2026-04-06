import React from 'react';

interface SkillRankStepperProps {
  value: number;
  onDelta: (delta: 1 | -1) => void;
  disabledMinus?: boolean;
  disabledPlus?: boolean;
}

export const SkillRankStepper: React.FC<SkillRankStepperProps> = ({
  value,
  onDelta,
  disabledMinus,
  disabledPlus,
}) => (
  <div className="skill-rank-stepper">
    <button
      type="button"
      className="skill-rank-btn"
      aria-label="Decrease ranks"
      disabled={disabledMinus}
      onClick={() => onDelta(-1)}
    >
      −
    </button>
    <span className="skill-rank-value" aria-live="polite">
      {value}
    </span>
    <button
      type="button"
      className="skill-rank-btn"
      aria-label="Increase ranks"
      disabled={disabledPlus}
      onClick={() => onDelta(1)}
    >
      +
    </button>
  </div>
);
