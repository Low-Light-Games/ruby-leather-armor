import { createGlossaryEntry } from '../createGlossaryEntry';

export const ARCANE_SPELL_FAILURE_GLOSSARY = createGlossaryEntry(
  'Arcane Spell Failure',
  'When casting an arcane spell with somatic components, rolling under this percentage on d% means the spell fails with no effect but the slot is still used.',
  'Armor and shields are the usual sources. Some classes or options reduce or ignore this chance.',
);
