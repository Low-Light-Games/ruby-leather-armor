# Step 8b: Macro Narrative Update

**File:** `app/services/dungeon_master/steps/context_update.rb`
**Template:** `app/services/dungeon_master/templates/macro_narrative_update.text.erb`
**Pipeline step name:** `macro_narrative_update`

## Purpose

Updates the adventure's `story_summary` field, the high-level "story so
far" that carries across the entire adventure. Only runs when the
beacon flagged the action as `macro_significant`.

## Input

| Field | Source |
|---|---|
| System prompt | `macro_narrative_update.text.erb` bound with: story hook/title, current story summary, factual outcome (`what_happened`) |
| User message | "Update the story summary." |

## Output (JSON)

```json
{
  "story_summary": "Updated story-so-far summary (3-8 sentences)",
  "reasoning": "What was added/changed"
}
```

## Execution

Steps 8a and 8b run **in parallel** (Ruby threads). The macro update is
conditional and only fires when `macro_significant` is true. If both
run, they execute concurrently since they write to different fields.

## Design rationale

The story summary feeds into every future Narrate prompt, giving the DM
long-term memory. But updating it on every turn would cause bloat and
inaccuracy. The `macro_significant` flag from the beacon acts as a
filter: only story-changing events (quest completion, boss defeat, plot
revelation) trigger an update.
