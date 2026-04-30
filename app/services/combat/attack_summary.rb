# frozen_string_literal: true

module Combat
  # Human-readable wrap-up of one resolved attack — attacker / target /
  # weapon labels plus a single sentence ("Goblin (shortsword) vs You:
  # 17 vs AC 14 — hits for 4 piercing damage."). Persisted alongside
  # the dice payload in Combat::NpcAttackOutcome.
  class AttackSummary
    # @param actors [Hash{attacker:, target_sheet:, target_kind:}]
    # @param weapon [Hash]
    # @param dice [Hash{attack_roll:, damage:, target_state:}]
    # @return [Hash]
    def self.build(actors:, weapon:, dice:)
      new(actors: actors, weapon: weapon, dice: dice).to_h
    end

    def initialize(actors:, weapon:, dice:)
      @attacker = actors[:attacker]
      @target_sheet = actors[:target_sheet]
      @target_kind = actors[:target_kind]
      @weapon = weapon
      @attack_roll = dice[:attack_roll]
      @damage = dice[:damage]
      @target_state = dice[:target_state]
    end

    def to_h
      {
        attacker_name: @attacker.name,
        target_name: target_label,
        weapon_label: @weapon[:label],
        message: human_message
      }
    end

    private

    def target_label
      @target_kind == :player ? 'You' : @target_sheet.name.to_s
    end

    def human_message
      core = attack_core_phrase
      return "#{core}." unless @attack_roll[:hit] && @damage

      "#{core} for #{damage_phrase}#{drop_phrase}."
    end

    def attack_core_phrase
      verb = @attack_roll[:hit] ? 'hits' : 'misses'
      "#{@attacker.name} (#{@weapon[:label]}) vs #{target_label}: " \
        "#{@attack_roll[:total]} vs AC #{@attack_roll[:defense_dc]} — #{verb}"
    end

    def damage_phrase
      type = @damage[:type]
      type.present? ? "#{@damage[:total]} #{type} damage" : "#{@damage[:total]} damage"
    end

    def drop_phrase
      return '' unless @target_state[:dropped]

      return ', you fall unconscious!' if @target_kind == :player

      ", dropping #{target_label}"
    end
  end
end
