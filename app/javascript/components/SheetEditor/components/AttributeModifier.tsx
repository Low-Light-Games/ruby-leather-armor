interface AttributeModifierProps {
  attributeValue: number;
}

export const AttributeModifier = ({
    attributeValue,
}: AttributeModifierProps) => {
  const modifier = Math.trunc(Math.ceil((attributeValue - 11) / 2));
  const modifierClass = modifier > 0 ? 'positive' : modifier < 0 ? 'negative' : 'zero';
    
  return (
    <span className={`attribute-modifier ${modifierClass}`}>
      {modifier > 0 ? '+' : ''} {modifier}
    </span>
  )
}
