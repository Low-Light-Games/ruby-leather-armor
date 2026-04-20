# frozen_string_literal: true

module DungeonMaster
  module PromptViews
    class MechEvalPromptContext
      attr_reader :domain, :character_block, :micro_context, :creature_stats, :rules_text, :prior_outcomes, :domain_instructions

      def initialize(domain:, character_block:, micro_context:, creature_stats:, rules_text:, prior_outcomes:, domain_instructions: nil, include_npc_actions_guidance: true, attack_options_text: nil, previous_summaries: [])
        @domain = domain
        @character_block = character_block
        @micro_context = micro_context
        @creature_stats = creature_stats
        @rules_text = rules_text
        @prior_outcomes = prior_outcomes
        @domain_instructions = domain_instructions
        @include_npc_actions_guidance = include_npc_actions_guidance
        @attack_options_text = attack_options_text
        @previous_summaries = previous_summaries
      end

      def include_npc_actions_guidance?
        @include_npc_actions_guidance
      end

      def attack_options_text
        @attack_options_text
      end

      def previous_summaries
        @previous_summaries
      end

      def with_domain_instructions(domain_instructions)
        with(domain_instructions: domain_instructions)
      end

      def with_combat_options(attack_options_text:, previous_summaries: [])
        with(
          attack_options_text: attack_options_text,
          previous_summaries: previous_summaries
        )
      end

      def with(overrides = {})
        self.class.new(**to_h.merge(overrides))
      end

      def to_h
        {
          domain: domain,
          character_block: character_block,
          micro_context: micro_context,
          creature_stats: creature_stats,
          rules_text: rules_text,
          prior_outcomes: prior_outcomes,
          domain_instructions: domain_instructions,
          include_npc_actions_guidance: include_npc_actions_guidance?,
          attack_options_text: attack_options_text,
          previous_summaries: previous_summaries
        }
      end
    end
  end
end
