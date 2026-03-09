# Unified Evaluation (alternative mode)

**File:** `app/services/dungeon_master/steps/unified_evaluation.rb`
**Template:** `app/services/dungeon_master/templates/unified_evaluation.text.erb`
**Pipeline step name:** `unified_evaluation`

## Purpose

A single-call alternative to the standard beacon + mechanical evaluation +
roll qualifier pipeline. Evaluates all six game domains at once, determining
which are affected, what rolls are needed, and whether Take 10/Take 20 is
eligible — all in one AI response.

Activated when `DmConfig` `evaluation_mode` is set to `"unified"`.

## Trade-offs vs. standard path

| | Standard Path | Unified Evaluation |
|---|---|---|
| AI calls | 8-14 (6 beacons + N mech evals + N roll qualifiers) | 1 |
| Cross-domain coherence | Low (each domain isolated) | High (single context) |
| Roll deduplication | Code-side post-merge | AI avoids duplicates natively |
| Per-domain model selection | Yes | No |
| Per-domain token budget | Yes | No (single large budget) |
| Prompt size | Small per call (~400-500 tokens) | Large (~1500+ tokens) |
| Target models | Any (cheap models work well) | Top-end only (o3, gpt-5, claude-4-opus) |
| Debugging | Per-domain logs | Single combined log |

## Input

| Field | Source |
|---|---|
| System prompt | `unified_evaluation.text.erb` bound with: full character block, all micro-contexts, creature stats, rules manifest briefs, story locations, scene summary, all beacon partials, all mecheval partials |
| User message | Pure intention from PlayerInterpreter |

## Output (JSON)

```json
{
  "domains": {
    "traversal": {
      "affected": true,
      "needs_mechanics": false,
      "macro_significant": false,
      "rules_needed": [],
      "domain_interpretation": "...",
      "transition": null,
      "destination": "Forest Camp",
      "combatants": [],
      "player_rolls": [],
      "npc_actions": [],
      "consequences": [],
      "mechanical_summary": ""
    },
    "exploration": {
      "affected": true,
      "needs_mechanics": true,
      "macro_significant": false,
      "rules_needed": ["perception_checks"],
      "domain_interpretation": "...",
      "transition": null,
      "destination": null,
      "combatants": [],
      "player_rolls": [
        {
          "type": "skill_check",
          "skill": "Perception",
          "dc": 15,
          "description": "Notice hidden tracks",
          "take_10_eligible": true,
          "take_20_eligible": true,
          "situational_modifiers": []
        }
      ],
      "npc_actions": [],
      "consequences": [],
      "mechanical_summary": "Perception check to notice tracks near camp"
    },
    "combat": { "affected": false, "..." : "..." },
    "social": { "affected": false, "..." : "..." },
    "rest": { "affected": false, "..." : "..." },
    "inventory": { "affected": false, "..." : "..." }
  },
  "reasoning": "Player is walking to the forest camp and looking around..."
}
```

## App-side post-processing

1. `parse_unified_response` splits the AI output into two values matching the
   standard pipeline contract:
   - `intent` — same shape as `converge_beacons` output
   - `evaluations` — same shape as `run_mechanical_evaluation_loop` output
2. `apply_qualifier_results` runs code-side for each evaluation to compute
   Take 10/Take 20 values from the character sheet (skill modifier + 10 or + 20).
3. From this point, the rest of the pipeline proceeds identically to the standard
   path: sanity checks, merge, dedup, auto-success filter, verdict, time keeper,
   output phase.

## What is NOT replaced

The unified evaluation replaces only the evaluation phase. These steps remain
separate and unchanged:

- Sanitize + Classify (gate)
- Sequencer
- PlayerInterpreter
- SanityChecker (world consistency + capability check)
- Verdict
- TimeKeeper
- Chronicler
- Narrate
- Context Update
- Macro Narrative Update

## Design rationale

The standard path's strength is decomposition: cheap models handle focused
prompts well. The unified path's strength is coherence: a top-end model can
see all domains at once and avoid duplicate rolls, cross-domain conflicts,
and missed interactions that the separated path sometimes produces.

The unified path is not a replacement — it is a toggle-gated alternative
(see [Design Philosophy](../design_philosophy.md) principles #3, #4, #10,
#11). The admin enables it when they have access to a sufficiently capable
model and want fewer AI calls with better cross-domain reasoning.

See also: [Edge Pipeline](edge_pipeline.md) for the fully monolithic
alternative that replaces the entire pipeline with one call.
