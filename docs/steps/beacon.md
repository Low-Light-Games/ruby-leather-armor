# Beacon (parallel per-domain interpretation)

**File:** `app/services/dungeon_master/steps/beacon.rb`
**Template:** `app/services/dungeon_master/templates/beacon.text.erb`
**Pipeline step name:** `beacon`

## Purpose

Parallel per-domain interpretation. Given the pure intention from the
PlayerInterpreter step, each domain beacon evaluates how the action
affects its domain (combat, traversal, social, exploration, rest,
inventory). Results are merged by a code-based convergence step.

## Domain selection

All six domains are always dispatched. The `interpreter_scope` config is
deprecated — `beacon_domains` always returns all domains.

## Input (per domain)

| Field | Source |
|---|---|
| System prompt | `beacon.text.erb` bound with: domain name, domain-specific character data, domain micro-context, domain rules manifest, domain-specific instruction partial, extra context (story locations for traversal) |
| User message | The intention string (from PlayerInterpreter step) |

## Output (JSON, per domain)

```json
{
  "affected": false,
  "needs_mechanics": false,
  "macro_significant": false,
  "rules_needed": [],
  "domain_interpretation": "How this action relates to this domain",
  "transition": null,
  "destination": null,
  "reasoning": "Brief explanation"
}
```

## Convergence (code-only)

`converge_beacons` merges all domain results into a unified intent hash:

- `affected_contexts`: domains where `affected == true`
- `needs_mechanics`: any affected domain needs mechanics
- `macro_significant`: any domain flagged it
- `rules_needed`: union of all affected domains' rules
- `primary_context`: derived from beacons using a DOMAIN_PRIORITY heuristic
  (combat > social > traversal > exploration > rest > inventory), not from
  Classify's category
- `destination`: from traversal beacon (used by TimeKeeper for journey distance)
- `plot_relevant`: determined by `determine_plot_relevance`, which now
  accepts `affected_contexts` (the full set) instead of `primary_context` only

## Error handling

Individual beacon failures are non-fatal. A failed beacon returns
`affected: false`, ensuring the pipeline can continue with the remaining
domains. The error is logged.

## Design rationale

The beacon pattern gives each domain focused attention. A combat
beacon can reason about AoO triggers without being distracted by
traversal movement rules. Running them in parallel means wall-clock time
equals the slowest single domain, not the sum of all domains.

The name "Beacon" conveys that the step signals all domains simultaneously
(see naming convention in `docs/design_philosophy.md`).

See [Design Philosophy - Prompt isolation](../design_philosophy.md) and
[Decision 25: Beacon](../pipeline_steps.md).
