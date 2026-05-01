# frozen_string_literal: true

module DungeonMaster
  # Output of the evaluation step (RollRequest out-of-combat,
  # CombatRollRequest in-combat free-text). Holds the player's intent, the
  # single roll spec the model emitted (or none), and the cross-cutting
  # signals downstream pipeline steps consume — combat-start handoff,
  # social-scene expansion, traversal destination.
  #
  # The hash payload flowing through PipelineFlowResults to Stagehand /
  # narration / context-update is built from this object via
  # {#to_intent_hash}; everything inside AdventureLoopResolution works
  # with the value object directly.
  #
  # @!attribute [r] player_rolls
  #   Mutable in place by deduplicate / auto-success / request_id passes
  #   in {AdventureLoopResolution#build_merged_from_result}.
  class EvaluationResult
    attr_reader :intention, :affected_contexts, :primary_domain,
                :destination, :combat_transition, :combat_combatants,
                :consequences, :mechanical_summary
    attr_accessor :player_rolls

    # rubocop:disable Metrics/ParameterLists
    def initialize(intention:, affected_contexts:,
                   destination: nil, expand_scene: false, macro_significant: false,
                   combat_transition: nil, combat_combatants: [], combat_ending: false,
                   player_rolls: [], consequences: [], mechanical_summary: '')
      @intention = intention.to_s
      @affected_contexts = Array(affected_contexts).map(&:to_s).reject(&:blank?).uniq
      @primary_domain = @affected_contexts.first
      @destination = destination.presence
      @expand_scene = expand_scene == true
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
    def expand_scene? = @expand_scene
    def macro_significant? = @macro_significant
    def combat_ending? = @combat_ending
    def social_scene_only? = expand_scene? && @affected_contexts == ['social']

    def combat_starting?
      @combat_transition.present? &&
        DungeonMaster::CombatTransitions.start?(@combat_transition)
    end

    # Hash flowing through PipelineFlowResults to downstream consumers
    # (Stagehand combat-init, AccumulatedAssembly, Chronicler) that still
    # read the legacy `intent` shape.
    def to_intent_hash
      {
        intention: @intention,
        expand_scene: @expand_scene,
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
          expand_scene: domain == 'social' && @expand_scene,
          transition: domain == 'combat' ? @combat_transition : nil,
          destination: domain == 'traversal' ? @destination : nil,
          combatants: domain == 'combat' ? @combat_combatants : []
        }]
      end
    end
  end
end
