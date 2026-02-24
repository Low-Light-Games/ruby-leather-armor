import { AttributeType } from '../../../types';

interface AttributeRowProps {
  attribute: AttributeType;
  value: number;
  onChange: (attribute: AttributeType, operation: 'increase' | 'decrease') => void;
  canIncrease: boolean;
  canDecrease: boolean;
}

export const AttributeRow = ({
  attribute,
  value,
  onChange,
  canIncrease,
  canDecrease
}: AttributeRowProps) => {
  return (
    <div>
      <p className="attribute-row">
        <span>
          <span>{attribute}:</span>
          <span>{value}</span>
        </span>
        <button 
          onClick={() => onChange(attribute, 'increase')}
          disabled={!canIncrease}
          aria-label={`Increase ${attribute}`}
          title={!canIncrease ? 'Cannot increase: max value reached or insufficient points' : `Increase ${attribute}`}
        >
          +
        </button>
        <button 
          onClick={() => onChange(attribute, 'decrease')}
          disabled={!canDecrease}
          aria-label={`Decrease ${attribute}`}
          title={!canDecrease ? 'Cannot decrease: minimum value reached' : `Decrease ${attribute}`}
        >
          -
        </button>
      </p>
    </div>
  )
}
