interface TagListEditorProps {
  items: string[]
  onChange: (items: string[]) => void
  placeholder?: string
  addLabel?: string
}

const TagListEditor = ({
  items, onChange, placeholder = '', addLabel = '+ Add',
}: TagListEditorProps) => (
  <div className="tag-list">
    {items.map((item, i) => (
      <div key={i} className="tag-item">
        <input
          type="text"
          value={item}
          onChange={e => onChange(items.map((v, j) => j === i ? e.target.value : v))}
          placeholder={placeholder}
        />
        <button
          className="btn-remove-sm"
          onClick={() => onChange(items.filter((_, j) => j !== i))}
        >
          &#x2715;
        </button>
      </div>
    ))}
    <button className="btn-add-sm" onClick={() => onChange([...items, ''])}>
      {addLabel}
    </button>
  </div>
)

export default TagListEditor
