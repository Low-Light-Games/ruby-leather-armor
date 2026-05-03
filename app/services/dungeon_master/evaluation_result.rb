# frozen_string_literal: true

module DungeonMaster
  class EvaluationResult
    attr_reader :intention, :affected_contexts, :primary_domain,
                :destination, :combat_transition, :combat_combatants,
                :consequences, :mechanical_summary
    attr_accessor :player_rolls

    # rubocop:disable Metrics/ParameterLists
    def initialize(intention:, affected_contexts:,
                   destination: nil, macro_significant: false,
                   combat_transition: nil, combat_combatants: [], combat_ending: false,
                   player_rolls: [], consequences: [], mechanical_summary: '')
      @intention = intention.to_s
      @affected_contexts = Array(affected_contexts).map(&:to_s).reject(&:blank?).uniq
      @primary_domain = @affected_contexts.first
      @destination = destination.presence
      @macro_significant = macro_significant == true
      @combat_transition = combat_transition.to_s.presence
      @combat_combatants = Array(combat_combatants).map(&:to_s).reject(&:blank?)
      @combat_ending = combat_ending == true
      @player_rolls = Array(player_rolls)
      @consequences = Array(consequences).map(&:to_s).reject(&:blank?)
      @mechanical_summary = mechanical_summary.to_s
    end
    # rubocop:enable Metrics/ParameterLists

    def affected? = !@affected_contexts.empty?
    def macro_significant? = @macro_significant
    def combat_ending? = @combat_ending

    def combat_starting?
      @combat_transition.present? &&
        DungeonMaster::CombatTransitions.start?(@combat_transition)
    end

    def to_intent_hash
      {
        intention: @intention,
        destination: @destination,
        affected_contexts: @affected_contexts,
        transition: @combat_transition,
        macro_significant: @macro_significant,
        combat_ending: @combat_ending,
        domain_results: build_domain_results
      }
    end

    private

    def build_domain_results
      @affected_contexts.to_h do |domain|
        [domain, {
          domain: domain,
          affected: true,
          macro_significant: false,
          transition: domain == 'combat' ? @combat_transition : nil,
          destination: domain == 'traversal' ? @destination : nil,
          combatants: domain == 'combat' ? @combat_combatants : []
        }]
      end
    end
  end
end
