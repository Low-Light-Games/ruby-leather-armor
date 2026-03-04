# Step 1b: Classify

**File:** `app/services/dungeon_master/steps/triage.rb` (`run_classify`)
**Template:** `app/services/dungeon_master/templates/classify.text.erb`
**Pipeline step name:** `classify`

## Purpose

Action classifier. Categorizes the player input into exactly one game
domain. Runs in parallel with Sanitize.

## Input

| Field | Source |
|---|---|
| System prompt | `classify.text.erb` (static, no dynamic bindings) |
| User message | Raw player input (unmodified) |

## Output (JSON)

```json
{
  "category": "traversal",
  "classification_reasoning": "why this category was chosen"
}
```

Valid categories: `combat`, `traversal`, `social`, `exploration`, `rest`,
`inventory`, `dm_query`.

## App-side post-processing

- The `category` is normalized and validated against the allowed list;
  unrecognized categories raise `AiError`.
- If `category == "dm_query"`, the pipeline branches to the DM Query fast
  path.
- Otherwise, the category is passed to the InterpretationDispatcher to
  influence domain selection (when `interpreter_scope` is `"filtered"`).

## Design rationale

Classification is based on **purpose**, not surface mechanics. "I cast
Mount and ride to the village" is `traversal`, not `combat`. The template
includes explicit rules for this to prevent misclassification of utility
spells and in-character dialogue.

See [Decision 20: Purpose-based classification](../pipeline_steps.md#20-purpose-based-classification)
and [Decision 24: Sanitize/Classify split](../pipeline_steps.md#24-sanitizeclassify-split-parallel-gate).
