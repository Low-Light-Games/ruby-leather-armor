# frozen_string_literal: true

module Combat
  class NpcAttackOutcome
    attr_reader :summary, :attack_roll, :damage, :target_state

    # @param summary [Hash{attacker_name:, target_name:, weapon_label:, message:}]
    # @param attack_roll [Hash{hit:, natural:, total:, defense_dc:}]
    # @param damage [Combat::DamageRoll, nil] nil when the attack missed
    # @param target_state [Hash{hp_before:, hp_after:, dropped:}]
    def initialize(summary:, attack_roll:, damage:, target_state:)
      @summary = summary
      @attack_roll = attack_roll
      @damage = damage || { total: nil, type: nil }
      @target_state = target_state
    end

    def hit
      attack_roll[:hit]
    end

    def target_dropped
      target_state[:dropped]
    end

    def message
      summary[:message]
    end

    def to_h
      {
        'attacker_name' => summary[:attacker_name],
        'target_name' => summary[:target_name],
        'weapon_label' => summary[:weapon_label],
        'message' => summary[:message],
        'hit' => attack_roll[:hit],
        'natural' => attack_roll[:natural],
        'total' => attack_roll[:total],
        'defense_dc' => attack_roll[:defense_dc],
        'damage_total' => damage[:total],
        'damage_type' => damage[:type],
        'target_hp_before' => target_state[:hp_before],
        'target_hp_after' => target_state[:hp_after],
        'target_dropped' => target_state[:dropped]
      }
    end
  end
end
