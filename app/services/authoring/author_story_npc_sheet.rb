# frozen_string_literal: true

module Authoring
  class AuthorStoryNpcSheet
    MODEL_KEY    = "creature_generation"
    TEMPLATE_KEY = "authoring/creature_generation"

    ABILITY_SCORE_RANGE = (1..40).freeze
    AC_RANGE            = (1..50).freeze
    BAB_RANGE           = (0..30).freeze
    SPEED_RANGE         = (0..120).freeze
    CR_RANGE            = (1..30).freeze

    def self.call(story_npc:, user: nil, ai: nil, log: nil, config: nil)
      new(story_npc: story_npc, user: user, ai: ai, log: log, config: config).call
    end

    def initialize(story_npc:, user: nil, ai: nil, log: nil, config: nil)
      @story_npc = story_npc
      @user      = user
      @config    = config || DmConfig.instance
      @ai        = ai || Ai::Client.new(@config)
      @log       = log || Ai::Logging.new(adventure: nil, user: @user, dm_service: "standard")
    end

    # @return [Hash]
    def call
      raw_attrs = run_generation_call
      clamp_attrs(raw_attrs)
    end

    private

    def run_generation_call
      system_prompt, user_msg = Ai::PromptRenderer.render_with_user_message(
        TEMPLATE_KEY,
        creature_name: @story_npc.name,
        party_level:   default_party_level,
      )

      prompt_summary = "AuthorStoryNpcSheet — story_npc ##{@story_npc.id} (#{@story_npc.name})"

      result = @log.timed_chat_call(MODEL_KEY, prompt_summary, ai: @ai) do
        raw = @ai.chat(
          system_prompt: system_prompt,
          user_message:  user_msg,
          step_name:     MODEL_KEY,
          model:         @config.model_for(MODEL_KEY),
        )
        [raw, @ai.parse_json(raw)]
      end

      entries = result.is_a?(Array) ? result : [result]
      entries.first || {}
    end

    def default_party_level
      4
    end

    def clamp_attrs(raw)
      raw = {} unless raw.is_a?(Hash)

      {
        name:             @story_npc.name,
        creature_type:    raw["creature_type"].to_s.presence || "humanoid",
        cr:               clamp_int(raw["cr"], CR_RANGE, default: 3),
        strength:         clamp_int(raw["strength"],     ABILITY_SCORE_RANGE, default: 10),
        dexterity:        clamp_int(raw["dexterity"],    ABILITY_SCORE_RANGE, default: 10),
        constitution:     clamp_int(raw["constitution"], ABILITY_SCORE_RANGE, default: 10),
        intelligence:     clamp_int(raw["intelligence"], ABILITY_SCORE_RANGE, default: 10),
        wisdom:           clamp_int(raw["wisdom"],       ABILITY_SCORE_RANGE, default: 10),
        charisma:         clamp_int(raw["charisma"],     ABILITY_SCORE_RANGE, default: 10),
        ac:               clamp_int(raw["ac"],          AC_RANGE,    default: 10),
        base_attack:      clamp_int(raw["base_attack"], BAB_RANGE,   default: 0),
        speed:            clamp_int(raw["speed"],       SPEED_RANGE, default: 30),
        hp_formula:       normalize_hp_formula(raw["hp_formula"]),
      }
    end

    def clamp_int(value, range, default:)
      n = Integer(value) rescue nil
      return default if n.nil?

      n.clamp(range.min, range.max)
    end

    # @param raw [String, Array<String>]
    # @return [String] PF1e dice notation
    def normalize_hp_formula(raw)
      raw = Array(raw).join if raw.is_a?(Array)
      formula = raw.to_s.strip
      return "3d8" if formula.empty?

      return formula if formula =~ /\A\d+d\d+([+-]\d+)?\z/

      "3d8"
    end
  end
end
