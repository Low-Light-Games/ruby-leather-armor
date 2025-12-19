import { AttributeType } from '../../../types';

interface AttributeRowProps {
  attribute: AttributeType;
  value: number;
  onChange: (attribute: AttributeType, operation: 'increase' | 'decrease') => void;
}

export const AttributeRow = ({
  attribute,
  value,
  onChange
}: AttributeRowProps) => {
  return (
    <div>
      <p className="attribute-row">
        <span>
          <span>{attribute}:</span>
          <span>{value}</span>
        </span>
        <button onClick={() => onChange(attribute, 'increase')}>+</button>
        <button onClick={() => onChange(attribute, 'decrease')}>-</button>
      </p>
    </div>
  )
}
