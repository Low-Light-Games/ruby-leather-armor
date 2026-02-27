# frozen_string_literal: true

module DungeonMasterLight
  # Minimal AI service for enemy action selection during combat.
  # Presents the creature's available actions and current state,
  # asks the AI to pick ONE action. Falls back to simple heuristics
  # if the AI call fails.
  class EnemyAiService
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You control a creature in combat. Pick ONE action from the numbered list
      below that makes the most tactical sense for this creature type and
      personality. Consider:
      - Melee creatures prefer to close distance and attack
      - Ranged creatures prefer to keep distance
      - Wounded creatures may retreat
      - Intelligent creatures use better tactics than beasts

      Respond ONLY with valid JSON (no markdown, no code fences):
      { "action_index": 0, "reasoning": "brief explanation" }
    PROMPT

    def initialize(config, log)
      @config = config
      @ai = DungeonMaster::AiClient.new(config)
      @log = log
    end

    # @param creature [CreatureSheet]
    # @param actions [Array<Hash>] available actions with :description
    # @param encounter [Encounter]
    # @param participant [EncounterParticipant]
    # @return [Hash] the chosen action
    def choose_action(creature, actions, encounter, participant)
      return actions.first if actions.size <= 1

      begin
        action_list = actions.each_with_index.map { |a, i| "#{i}: #{a[:description]}" }.join("\n")

        hp_pct = creature.max_hp > 0 ? (participant.current_hp.to_f / creature.max_hp * 100).round : 100
        user_message = <<~MSG
          Creature: #{creature.name} (#{creature.creature_type}, #{creature.race || 'unknown'} #{creature.character_class || 'creature'}, level #{creature.level})
          HP: #{participant.current_hp}/#{creature.max_hp} (#{hp_pct}%)
          Position: (#{participant.position_x}, #{participant.position_y})

          Available actions:
          #{action_list}
        MSG

        raw = @ai.chat(
          system_prompt: SYSTEM_PROMPT,
          user_message: user_message,
          max_tokens: 150
        )

        parsed = @ai.parse_json(raw)
        @log.ai_log!(
          "enemy_ai", "Enemy AI for #{creature.name}", raw, parsed,
          parse_status: @ai.last_parse_status,
          request_body: { system_prompt: SYSTEM_PROMPT, user_message: user_message }
        )

        index = parsed["action_index"].to_i
        index = index.clamp(0, actions.size - 1)
        actions[index]

      rescue => e
        @log.dm_log!("Enemy AI failed for #{creature.name}: #{e.message} — using heuristic fallback")
        heuristic_fallback(actions, participant)
      end
    end

    private

    # Simple fallback: prefer melee > move_and_attack > ranged > move > retreat
    def heuristic_fallback(actions, participant)
      priority = %w[melee_attack move_and_attack ranged_attack move retreat]

      priority.each do |type|
        match = actions.find { |a| a[:type] == type }
        return match if match
      end

      actions.first
    end
  end
end
