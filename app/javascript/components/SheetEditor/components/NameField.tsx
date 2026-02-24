import type { Dispatch, SetStateAction } from 'react'

interface NameFieldProps {
  name: string;
  onChange: Dispatch<SetStateAction<string>>;
}

export const NameField = ({ name, onChange }: NameFieldProps) => {
  return (
    <input 
      id="character-name"
      type="text" 
      value={name} 
      onChange={(e) => onChange(e.target.value)}
      placeholder="Enter character name"
      aria-label="Character name"
    />
  )
}