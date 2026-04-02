import { AttributeType } from '../../../types';
import { formatMod } from '../../../utils/formatting';
import { AttributeModifier } from './AttributeModifier';

interface AttributeRowProps {
  attribute: AttributeType;
  value: number;
  racialModifier: number;
  onChange: (attribute: AttributeType, operation: 'increase' | 'decrease') => void;
  canIncrease: boolean;
  canDecrease: boolean;
}

export const AttributeRow = ({
  attribute,
  value,
  racialModifier,
  onChange,
  canIncrease,
  canDecrease
}: AttributeRowProps) => {
  const finalValue = value + racialModifier;
  

  return (
    <div>
      <p className="attribute-row">
        <span>
          <span>
            {attribute} <AttributeModifier attributeValue={value} />
          </span>
          <span className="attribute-values">
            {racialModifier !== 0 ? (
              <>
                <span className="base-value">{value}</span>
                <span className={`racial-mod ${racialModifier > 0 ? 'positive' : 'negative'}`}>
                  ({formatMod(racialModifier)})
                </span>
                <span className="equals">=</span>
                <span className="final-value">{finalValue}</span>
              </>
            ) : (
              <span>{value}</span>
            )}
          </span>
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
