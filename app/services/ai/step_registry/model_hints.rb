# frozen_string_literal: true

module Ai
  module StepRegistry
    module ModelHints
      FAST_CHEAP = 'Fast, cheap model. e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.'

      INTAKE = "#{FAST_CHEAP} Security gate + context suggestion.".freeze

      GAME_MASTER = "#{FAST_CHEAP} Out-of-combat orchestrator opted into " \
                    'per-adventure via the use_gamemaster_orchestrator flag. ' \
                    "First iteration emits narrative directly; tools land later.".freeze

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

      COMBAT_CONTEXT_UPDATE = 'Mid-tier model. JSON update for combat state. ' \
                              'Must preserve canonical combat identity. ' \
                              'e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.'

      EXTRACT_FROM_PREMISE = 'Capable model recommended. Story-save fact extraction reads the ' \
                             'spoiler-bearing premise + player-facing opening_message and emits ' \
                             'a coherent seed_facts list — e.g. gpt-4.1, gpt-4.1-mini, gpt-5-mini.'

      GENERATE_OPENING_MESSAGE = 'Capable model recommended. JIT opening-scene generator for ' \
                                 'pre-validation stories whose opening_message is blank — ' \
                                 'e.g. gpt-4.1, gpt-4.1-mini, gpt-5-mini.'

      CREATURE_GENERATION = 'Mid-tier model recommended. Must produce valid PF1e stat blocks ' \
                            '— e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.'

      ROLL_REQUEST = 'Cheapest reasoning model — defaults to gpt-5-nano ($0.05/$0.40 per M, ' \
                     'reasoning) at reasoning_effort=minimal. Single AI call out of combat ' \
                     'with RAG-retrieved rules + beats and no character block in the prompt. ' \
                     'Override only if you want non-reasoning behavior, a more capable model, ' \
                     'or higher reasoning effort on this step.'

      CAST_RESOLVER = 'Cheapest reasoning model — same tier as RollRequest. Single AI call ' \
                      'between Sequencer and RollRequest that emits [{name,type,count}] for ' \
                      'every creature implicated by the player\'s intent + scene context. ' \
                      'Stats and identifiers come from the deterministic 4-tier lookup in ' \
                      'Encounters::CastResolver, not from this prompt.'

      INTERPRETER = 'Capable model recommended (e.g. gpt-5-mini at low effort). Per-action ' \
                    'reference resolver — rewrites one atomic Sequencer action into a fully ' \
                    'self-contained sanitized intent statement so downstream steps need no ' \
                    'conversation context. Runs in parallel with CastResolver inside the ' \
                    'per-action loop. Cheap nano models pattern-match on examples but cannot ' \
                    'reliably carry the expansion move (see §3 pivot).'

      REQUEST_ROLL_TOOL = "#{FAST_CHEAP} Tool-flavored RollRequest invoked by the " \
                          "GameMaster. Slim schema (no needs_roll, no transition signals); " \
                          'GM has already decided a roll is required.'.freeze

      COMBAT_ROLL_REQUEST = 'Cheapest reasoning model — defaults to gpt-5-nano at ' \
                            'reasoning_effort=minimal. Single AI call when the player types ' \
                            'free-text mid-combat. Carries attack options, action economy, ' \
                            'threats, and battlefield text; emits attack_option_id (never DC) ' \
                            'for combat rolls. Combat math resolves post-call from the sheet ' \
                            'via CombatMechanicResolution.'

      LOREMASTER = 'Mid-tier model. Structured fact extraction from Narrate output — ' \
                   'e.g. gpt-4o-mini, gpt-4.1-mini, gpt-5-nano. Runs after Narrate, ' \
                   'in parallel with SocialMaster/Geomaster (masters fan-out).'

      SOCIAL_MASTER = 'Cheapest model. Runtime NPC extraction from Narrate output — ' \
                      'e.g. gpt-5-nano, gpt-4o-mini. Runs after Narrate, in parallel ' \
                      'with Loremaster/Geomaster (masters fan-out).'

      GEOMASTER = 'Cheapest model. Runtime location extraction from Narrate output — ' \
                  'e.g. gpt-5-nano, gpt-4o-mini. Runs after Narrate, in parallel ' \
                  'with Loremaster/SocialMaster (masters fan-out).'

      OOC_RESPONDER = 'Cheapest model. Answers out-of-character player questions about the ' \
                      'game, rules, and app. Short-circuits the pipeline — e.g. gpt-5-nano.'

      COMBAT_BOOKEND = 'Creative model. Short epilogue (2-4 sentences) summarising a combat ' \
                       'conclusion (victory or death). Called once at combat end, not part of ' \
                       'the turn pipeline — e.g. gpt-4.1, gpt-5-nano, gpt-5.'
    end
  end
end
