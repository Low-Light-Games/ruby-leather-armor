# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Mechanic (post-rolls arbitration).
    # Resolves dice roll results against mechanical evaluation summaries and
    # produces structured mutations (HP changes, conditions, items consumed).
    module Mechanic
      private

      def run_mechanic(intent, merged, roll_results:, npc_results:)
        prompt_summary = "Mechanic: \"#{@log.truncate(intent[:intention])}\""

        raise Ai::Error, "Mechanic step reached without a character sheet — cannot resolve mechanics" unless @sheet

        char_block = CharacterBlock.full(@sheet)
        all_roll_results = [roll_results, npc_results].reject(&:blank?).join("\n\n")
        scene_facts = retrieve_scene_facts_for_mechanic(intent)

        system_prompt = Ai::PromptRenderer.render("mechanic",
          character_block: char_block,
          mechanical_summaries_text: merged[:mechanical_summaries].join("\n\n"),
          roll_results: all_roll_results,
          consequences: merged[:consequences].present? ? merged[:consequences].to_json : nil,
          scene_facts: scene_facts,
          class_ability_buff_reference: class_ability_buff_reference_for_prompt,
          no_auto_hit_miss: @config.no_auto_hit_miss?)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("mechanic", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                          step_name: "mechanic", model: @config.model_for("mechanic"))
          [raw, @ai.parse_json(raw)]
        end

        raise Ai::Error, "Mechanic step returned no outcome — model produced: #{parsed.inspect.truncate(200)}" unless parsed["outcome"].present?

        {
          outcome: parsed["outcome"],
          mutations: parsed["mutations"] || {}
        }
      end

      def retrieve_scene_facts_for_mechanic(intent)
        DungeonMaster::SceneFacts::ForResolution.call(
          adventure:   @adventure,
          intent_text: intent[:intention].to_s,
          ai:          @ai,
          log:         @log,
        )
      end

      def class_ability_buff_reference_for_prompt
        ClassAbilityDefinition.order(:id).map do |definition|
          if definition.effects.present?
            %(• #{definition.id} (#{definition.name}): {"id":"#{definition.id}","source_type":"class_ability"})
          else
            %(• #{definition.id} (#{definition.name}): {"id":"#{definition.id}","source_type":"class_ability","adjudicated_effects":[{"target":"…","bonusType":"…","bonus":N}],"adjudicated_duration_hours": hours})
          end
        end.join("\n")
      end
    end
  end
end
