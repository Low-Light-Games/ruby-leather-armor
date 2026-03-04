# Step 3: InterpretationDispatcher

**File:** `app/services/dungeon_master/steps/interpretation_dispatcher.rb`
**Template:** `app/services/dungeon_master/templates/interpretation_dispatcher.text.erb`
**Pipeline step name:** `dispatcher`

## Purpose

Parallel per-domain interpretation. Given the pure intention from the
Intent step, each dispatcher evaluates how the action affects its domain
(combat, traversal, social, exploration, rest, inventory). Results are
merged by a code-based convergence step.

## Domain selection

Controlled by `DmConfig` `interpreter_scope`:
- `"all"` (default): all six domains are dispatched
- `"filtered"`: only the Classify category + active contexts are dispatched

## Input (per domain)

| Field | Source |
|---|---|
| System prompt | `interpretation_dispatcher.text.erb` bound with: domain name, domain-specific character data, domain micro-context, domain rules manifest, domain-specific instruction partial, extra context (story locations for traversal) |
| User message | The intention string (from Intent step) |

## Output (JSON, per domain)

```json
{
  "affected": false,
  "needs_mechanics": false,
  "macro_significant": false,
  "rules_needed": [],
  "domain_interpretation": "How this action relates to this domain",
  "transition": null,
  "time_spanning": false,
  "time_span_type": null,
  "destination": null,
  "estimated_hours": null,
  "reasoning": "Brief explanation"
}
```

## Convergence (code-only)

`converge_dispatchers` merges all domain results into a unified intent hash:

- `affected_contexts`: domains where `affected == true`
- `needs_mechanics`: any affected domain needs mechanics
- `macro_significant`: any domain flagged it
- `rules_needed`: union of all affected domains' rules
- `primary_context`: the Classify category if it's affected, otherwise the first affected domain
- `time_spanning`: true if traversal or rest dispatcher flagged it
- `plot_relevant`: determined by `determine_plot_relevance` (checks for undiscovered clues and story NPCs)

## Error handling

Individual dispatcher failures are non-fatal. A failed dispatcher returns
`affected: false`, ensuring the pipeline can continue with the remaining
domains. The error is logged.

## Design rationale

The dispatcher pattern gives each domain focused attention. A combat
dispatcher can reason about AoO triggers without being distracted by
traversal movement rules. Running them in parallel means wall-clock time
equals the slowest single domain, not the sum of all domains.

See [Design Philosophy - Prompt isolation](../design_philosophy.md) and
[Decision 25: InterpretationDispatcher](../pipeline_steps.md).
