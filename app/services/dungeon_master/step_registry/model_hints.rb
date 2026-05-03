# frozen_string_literal: true

module DungeonMaster
  module StepRegistry
    # Long-form model_hint strings for the admin UI, kept out of the
    # main registry hash so step_registry.rb itself stays a focused
    # table of contents.
    module ModelHints
      FAST_CHEAP = 'Fast, cheap model. e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.'

      INTAKE = "#{FAST_CHEAP} Security + dm_query detection + context suggestion.".freeze
      DM_QUERY = "#{FAST_CHEAP} Straightforward Q&A.".freeze
      SEQUENCER = "#{FAST_CHEAP} Compound action detection.".freeze
      SANITY_CHECKER = "#{FAST_CHEAP} Sheet validation. Only used in AI mode.".freeze

      SANITY_CHECKER_WORLD = '⚠️ Capable model REQUIRED. Cross-references player actions ' \
                             'against full game state. Unlikely to perform well with budget ' \
                             'models. Recommended: gpt-4o-mini or better (gpt-4.1-mini, ' \
                             'o3-mini, gpt-5-mini).'

      MECHANIC = '➡️ Capable model suggested. Post-roll arbitration and mutation generation — ' \
                 'e.g. o3-mini, o4-mini, gpt-5-mini.'

      COMBAT_GM = '➡️ Capable model required for active combat adjudication ' \
                  '(battlefield + PF1e) — e.g. o3-mini, gpt-5-mini.'

      TIME_KEEPER = "#{FAST_CHEAP} Estimates in-game time for an action.".freeze

      NARRATE = 'Creative model. Narrative quality scales with capability — ' \
                'e.g. gpt-4.1, gpt-4o, gpt-5.'

      COMBAT_CONTEXT_UPDATE = 'Mid-tier model. Domain-scoped JSON update for combat state. ' \
                              'Must preserve canonical combat identity. ' \
                              'e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.'

      SCENE_UPDATE = "#{FAST_CHEAP} Scene summary and new-creature signals.".freeze

      MACRO_NARRATIVE_UPDATE = 'Mid-tier model. Judges narrative significance — ' \
                               'e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.'

      CREATURE_GENERATION = 'Mid-tier model recommended. Must produce valid PF1e stat blocks ' \
                            '— e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.'

      ROLL_REQUEST = 'Cheapest reasoning model — defaults to gpt-5-nano ($0.05/$0.40 per M, ' \
                     'reasoning) at reasoning_effort=minimal. Single AI call out of combat ' \
                     'with RAG-retrieved rules + beats and no character block in the prompt. ' \
                     'Override only if you want non-reasoning behavior, a more capable model, ' \
                     'or higher reasoning effort on this step.'

      COMBAT_ROLL_REQUEST = 'Cheapest reasoning model — defaults to gpt-5-nano at ' \
                            'reasoning_effort=minimal. Single AI call when the player types ' \
                            'free-text mid-combat. Carries attack options, action economy, ' \
                            'threats, and battlefield text; emits attack_option_id (never DC) ' \
                            'for combat rolls. Combat math resolves post-call from the sheet ' \
                            'via CombatMechanicResolution.'

      COMBAT_NARRATOR = 'Creative model. Narrates a single deterministic combat round (PR-G of ' \
                        'the combat-determinism arc) — short sentences, weapon impact, second ' \
                        'person. Tight token budget; one paragraph. Tune prompt + model for ' \
                        'voice independently of the default narrate step. Runs async via ' \
                        'CombatNarratorJob so it never blocks End Turn.'

      NPC_ACTION = "#{FAST_CHEAP} Per-NPC combat action decision. Runs N in parallel via Node fan_out.".freeze

      LOREMASTER = 'Mid-tier model. Structured fact extraction from factual outcomes — ' \
                   'e.g. gpt-4o-mini, gpt-4.1-mini, gpt-5-nano. Runs in parallel with ' \
                   'Narrate/ContextUpdate, so latency is Narrate-bounded.'
    end
  end
end
