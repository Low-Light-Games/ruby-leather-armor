# frozen_string_literal: true

module Combat
  # Builds the JSON payload returned to the controller after an attack
  # resolves. Extracted from the resolver so the resolver code stays
  # focused on dispatch + state mutation, not on which keys the
  # frontend expects.
  #
  # Constructor takes three grouped hashes — the attack inputs, the
  # roll outcome, and the situational modifiers — keeping the
  # signature small enough for static analysis without a giant
  # positional argument list.
  class AttackResolutionPayload
    # @param attack_input [Hash] option, target_name, attack_bonus, defense_dc
    # @param attack_outcome [Hash] attack: roll, damage: roll, target_state
    # @param situational [Hash] flanking, flanking_bonus, cover, cover_bonus
    def initialize(attack_input:, attack_outcome:, situational:)
      @attack_input = attack_input
      @attack_outcome = attack_outcome
      @situational = situational
    end

    def to_h
      core_fields
        .merge(combat_fields)
        .merge(damage_fields)
        .merge(target_fields)
        .merge(situational_fields)
        .merge(message: message)
    end

    private

    def option
      @attack_input[:option]
    end

    def attack
      @attack_outcome[:attack]
    end

    def damage
      @attack_outcome[:damage]
    end

    def target_state
      @attack_outcome[:target_state]
    end

    def core_fields
      {
        kind: 'attack',
        attack_option_id: option[:id].to_s,
        attack_label: option[:label].to_s,
        target_name: @attack_input[:target_name],
        attack_mode: option[:attack_mode],
        defense_kind: option[:defense_kind]
      }
    end

    def combat_fields
      {
        attack_bonus: @attack_input[:attack_bonus],
        attack_natural: attack[:natural],
        attack_total: attack[:total],
        defense_dc: @attack_input[:defense_dc],
        crit_threat: attack[:natural] == 20,
        natural_one: attack[:natural] == 1,
        hit: attack[:hit]
      }
    end

    def damage_fields
      {
        damage_expression: option[:damage],
        damage_type: option[:damage_type],
        damage_natural: damage[:natural],
        damage_total: damage[:total]
      }
    end

    def target_fields
      {
        target_hp_before: target_state[:hp_before],
        target_hp_after: target_state[:hp_after],
        target_dropped: target_state[:dropped]
      }
    end

    def situational_fields
      {
        flanking: @situational[:flanking],
        flanking_bonus: @situational[:flanking_bonus],
        cover_bonus: @situational[:cover_bonus]
      }
    end

    def message
      verb = attack[:hit] ? 'hits' : 'misses'
      core = "#{option[:label]} vs #{@attack_input[:target_name]}: " \
             "#{attack[:total]} vs AC #{@attack_input[:defense_dc]} — #{verb}#{tag_suffix}"
      return "#{core}." unless attack[:hit] && damage[:total]

      "#{core} for #{damage_phrase} damage#{drop_suffix}."
    end

    def tag_suffix
      tags = []
      tags << '+2 flanking' if @situational[:flanking]
      tags << '+4 cover' if @situational[:cover_bonus].to_i.positive?
      tags.any? ? " (#{tags.join(', ')})" : ''
    end

    def damage_phrase
      type = option[:damage_type]
      type.present? ? "#{damage[:total]} #{type}" : damage[:total].to_s
    end

    def drop_suffix
      target_state[:dropped] ? ", dropping #{@attack_input[:target_name]}" : ''
    end
  end
end
