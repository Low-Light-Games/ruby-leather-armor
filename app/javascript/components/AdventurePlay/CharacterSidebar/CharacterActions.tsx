import { formatMod } from '../../../utils/formatting'

interface CharacterActionsProps {
  rollMeleeAttack: () => void
  rollRangedAttack: () => void
  rollInitiative: () => void
  rollConcentration: () => void
  concentrationMod: number | null
}

const CharacterActions = ({
  rollMeleeAttack, rollRangedAttack, rollInitiative,
  rollConcentration, concentrationMod,
}: CharacterActionsProps) => (
  <div className="roll-buttons">
    <h3>Actions</h3>
    <button className="roll-btn attack" onClick={rollMeleeAttack}>⚔️ Melee Attack</button>
    <button className="roll-btn ranged" onClick={rollRangedAttack}>🏹 Ranged Attack</button>
    <button className="roll-btn initiative" onClick={rollInitiative}>⏱️ Roll Initiative</button>
    {concentrationMod !== null && (
      <button
        className="roll-btn concentration"
        onClick={rollConcentration}
        title={`Concentration Check: d20 ${formatMod(concentrationMod)} (CL + casting ability mod)`}
      >
        🔮 Concentration ({formatMod(concentrationMod)})
      </button>
    )}
  </div>
)

export default CharacterActions
