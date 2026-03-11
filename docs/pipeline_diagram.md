# Dungeon Master Pipeline — Flow Diagram

High-level flow of the AI DM pipeline. For step-by-step detail see [Pipeline Steps](pipeline_steps.md).

```mermaid
flowchart TB
    subgraph entry["Entry"]
        A[Player Input] --> B[run_prompt]
    end

    subgraph gate["Gate (parallel)"]
        B --> C[Sanitize]
        B --> D[Classify]
        C --> E{Reject?}
        D --> E
        E -->|danger high| REJECT[Return :rejected]
        E -->|no| F{dm_query?}
    end

    F -->|yes| G[DM Query flow]
    G --> G1[resolve_plot stub]
    G1 --> G2[run_dm_query]
    G2 --> OUT_DM[Return :dm_query]

    F -->|no| H[orchestrate_actions]

    subgraph action_loop["Action loop"]
        H --> I[Sequencer]
        I --> J[Split into actions]
        J --> K[For each action]
        K --> L[Player Interpreter]
        L --> M[CoreResolver.resolve]
    end

    subgraph resolve["resolve (per action)"]
        M --> N[Beacon — all domains parallel]
        N --> N1[traversal]
        N --> N2[combat]
        N --> N3[social]
        N --> N4[exploration]
        N --> N5[rest]
        N --> N6[inventory]
        N1 & N2 & N3 & N4 & N5 & N6 --> O{needs_mechanics?}
    end

    O -->|yes| P[Full gate]
    O -->|no| Q[World consistency check]
    Q --> Q1{Consistent?}
    Q1 -->|no| REJECT
    Q1 -->|yes| R_NM[TimeKeeper]
    R_NM --> R_NM1{Encounter?}
    R_NM1 -->|yes| ENC
    R_NM1 -->|no| MOMENTUM[Momentum]
    MOMENTUM --> RES

    subgraph full_gate["Full gate (parallel)"]
        P --> P1[Mechanical evaluation loop]
        P --> P2[World consistency check]
        P --> P3[Capability check]
        P1 --> P1a[Per affected context]
        P2 --> P2a{Consistent?}
        P3 --> P3a{Allowed?}
    end

    P2a -->|no| REJECT
    P3a -->|no| REJECT
    P1a & P2a & P3a --> S[Merge evaluations]
    S --> T{Player rolls needed?}
    T -->|yes| PAUSE_ROLLS[Return :awaiting_rolls]
    T -->|no| U[finish_resolution]
    U --> V[Resolve NPC actions]
    V --> W[Mechanic]
    W --> X[Apply mutations]
    X --> R

    subgraph time_keeper["TimeKeeper"]
        R --> R1[Estimate time]
        R1 --> R2[Consult Harbinger]
        R2 --> R3[Advance GameClock]
        R3 --> R4{Encounter?}
        R4 -->|yes| ENC[Encounter path]
        R4 -->|no| RES[Accumulate :resolved]
    end

    ENC --> ENC1[Warmaster?]
    ENC1 --> ENC2{Initiative?}
    ENC2 -->|yes| PAUSE_INIT[Return :awaiting_initiative]
    ENC2 -->|no| RES

    M --> RESOLVED[resolved]
    M --> REJECT
    M --> PAUSE_ROLLS
    M --> PAUSE_INIT
    M --> ENC_RES[encounter]

    RES --> K
    ENC_RES --> K
    RESOLVED --> K

    K --> DONE{More actions?}
    DONE -->|yes| K
    DONE -->|no| PHASE[Output phase]

    subgraph output_phase["Output phase"]
        PHASE --> O1[resolve_plot]
        O1 --> O1a{Chronicler / heuristic}
        O1a --> O2[Stagehand: run_output_phase]
        O2 --> O2a{Combat started?}
        O2a -->|yes| PAUSE_INIT
        O2a -->|no| O3[Narration mode]
        O3 --> O3p[Narrate]
        O3 --> O3c[Context updates]
        O3p --> O3p1[run_narrate]
        O3c --> O3c1[Micro context update]
        O3c --> O3c2[Macro narrative update]
        O3c1 & O3c2 --> parallel["(parallel)"]
        O3p1 --> OUT_NARR[Return :narrated]
        parallel --> OUT_NARR
    end
```

## Resumption flows

```mermaid
flowchart LR
    subgraph roll_resume["Roll result submitted"]
        RR[run_rolls] --> RR1[Restore intent + merged]
        RR1 --> RR2[finish_resolution]
        RR2 --> RR3[Mechanic → Mutations → TimeKeeper]
        RR3 --> RR4{More in queue?}
        RR4 -->|yes| RR5[run_remaining_queue]
        RR4 -->|no| RR6[run_accumulated_output_phase]
        RR5 --> PHASE[Output phase]
        RR6 --> PHASE
    end

    subgraph init_resume["Initiative submitted"]
        II[run_initiative] --> II1[Warmaster.finalize_combat!]
        II1 --> II2{More in queue?}
        II2 -->|yes| II3[run_remaining_queue]
        II2 -->|no| II4[run_accumulated_output_phase]
        II3 --> PHASE
        II4 --> PHASE
    end
```

## Step summary

| Step | Purpose |
|------|--------|
| **Sanitize** | Score input safety; produce sanitized text. |
| **Classify** | Category: combat, traversal, social, exploration, rest, inventory, dm_query. |
| **Sequencer** | Split player message into discrete actions. |
| **Player Interpreter** | Per action: intent + context tags. |
| **Beacon** | Per domain (parallel): affected?, needs_mechanics?, rules_needed, transition, destination. |
| **Mechanical evaluation** | Per affected context: rolls, NPC actions, consequences, summary. |
| **Sanity checker** | World consistency + capability guardrail (parallel with mech eval). |
| **Mechanic** | Factual outcome + structured mutations from rolls + NPC results (mechanical path). |
| **Momentum** | Factual outcome + affected contexts for non-mechanical actions. |
| **TimeKeeper** | Estimate time → Harbinger (encounters) → GameClock advance. Stores journey_data on loop. |
| **Chronicler** | Plot/clue/NPC reaction brief for Narrate (if story data exists). Determines adventure_complete. |
| **Narrate** | Prose from outcome + contexts + dm_brief. Reads what_happened from loop. |
| **Micro context update** | Update affected + active context JSONBs. |
| **Macro narrative update** | Update story summary (if macro_significant). |

## Edge pipeline (alternative)

When `pipeline_mode: "edge"`, a single **Edge Pipeline** call replaces the full step sequence: one AI call handles sanitization, adjudication, narration, and state in one pass. See pipeline_steps.md for when to use it.
