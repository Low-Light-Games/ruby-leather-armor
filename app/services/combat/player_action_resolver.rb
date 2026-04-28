# frozen_string_literal: true

module Combat
  # Deterministic resolver for a single player combat action initiated from the
  # combat HUD (PR-B of the combat-determinism arc — see
  # docs/combat_redesign.md). The AI is NOT in this path; for the routine cases
  # — pick an attack option, pick a target, resolve hit + damage + HP delta —
  # this is the entire pipeline.
  #
  # Two dice strategies, selected by `User#combat_dice_strategy`:
  #
  #   * "server" — RNG happens here, the resolver returns the final
  #     `:resolved` result in one round-trip.
  #   * "client" — the resolver returns a `:awaiting_player_dice` payload
  #     describing the rolls the player needs to make. The frontend posts the
  #     natural results back; a second `.call` with `submitted_dice:` resolves
  #     the action.
  #
  # The same shape comes back to the controller in both branches so the
  # frontend has one rendering surface.
  #
  # PR-B is intentionally narrow: full AC vs the bare attack bonus from the
  # sheet. Flanking, AoO, cover, and reach are PR-D's job. Grid authority is
  # PR-C. Free-text combat ("I tip the brazier") still flows through the
  # existing `Steps::CombatGm` chain until PR-E.
  class PlayerActionResolver
    class Error < StandardError
      attr_reader :code

      def initialize(message, code: :resolver_error)
        super(message)
        @code = code
      end
    end

    SUPPORTED_KINDS = %w[attack move end_turn].freeze
    DEFENSE_KIND_TO_STAT = {
      'full_ac' => 'ac',
      'touch_ac' => 'touch_ac',
      'flat_footed_ac' => 'flat_footed_ac'
    }.freeze
    PLAYER_NAME = DungeonMaster::Utilities::CombatTurnCalculator::PLAYER_NAME

    def self.call(**)
      new(**).call
    end

    def initialize(adventure:, sheet:, user:, params:, submitted_dice: nil)
      @adventure = adventure
      @sheet = sheet
      @user = user
      @params = (params || {}).deep_symbolize_keys
      @submitted_dice = submitted_dice&.deep_symbolize_keys
    end

    def call
      ensure_combat_active!
      ensure_player_turn!
      ensure_supported_kind!

      case @params[:kind].to_s
      when 'attack'   then resolve_attack
      when 'move'     then resolve_move
      when 'end_turn' then resolve_end_turn
      end
    end

    private

    def resolve_attack
      option = lookup_attack_option!
      target = lookup_target!
      situational = situational_modifiers_for(option, target)
      attack_bonus = attack_bonus_for(option) + situational[:flanking_bonus]
      defense_dc = defense_dc_for(target, option) + situational[:cover_bonus]

      if @submitted_dice.nil? && client_dice?
        return awaiting_player_dice(option: option, target: target,
                                    attack_bonus: attack_bonus, defense_dc: defense_dc,
                                    situational: situational)
      end

      attack_natural, attack_total, hit = resolve_attack_dice(option: option,
                                                              attack_bonus: attack_bonus,
                                                              defense_dc: defense_dc)
      damage_natural, damage_total = resolve_damage_dice(option: option, hit: hit)

      apply_resolution(option: option, target: target, attack_bonus: attack_bonus,
                       defense_dc: defense_dc, attack_natural: attack_natural,
                       attack_total: attack_total, hit: hit,
                       damage_natural: damage_natural, damage_total: damage_total,
                       situational: situational)
    end

    # Computes flanking + cover modifiers from grid positions when both
    # the player and the target have canonical coordinates. When the
    # battlefield is missing a position we silently return zeros — PR-B's
    # bare-AC behavior is the safe fallback.
    def situational_modifiers_for(option, target)
      creature = target.first
      attacker_pos = Combat::Positions.player_position(@adventure)
      target_pos = Combat::Positions.position_for_creature_sheet(@adventure, creature.id)
      return zero_situational unless attacker_pos&.coordinates_present? && target_pos&.coordinates_present?

      others = Combat::Positions.for_adventure(@adventure)
      reach = Combat::Rules.reach_for(option)

      flanking = Combat::Rules.flanking?(attacker: attacker_pos, target: target_pos,
                                         allies: others, reach_squares: reach)
      cover = Combat::Rules.cover_between(attacker: attacker_pos, target: target_pos, others: others)

      {
        flanking: flanking,
        flanking_bonus: flanking ? Combat::Rules::FLANKING_BONUS : 0,
        cover: cover,
        cover_bonus: cover
      }
    end

    def zero_situational
      { flanking: false, flanking_bonus: 0, cover: 0, cover_bonus: 0 }
    end

    # ── Movement ────────────────────────────────────────────────────────

    # Click-to-move on the tactical grid. The frontend posts the target
    # square in world coordinates; here we validate it's in range, not
    # occupied, and pay the right action-economy cost (5-foot step when
    # distance == 1 and a move action is still available, otherwise a
    # standard move limited to player speed).
    #
    # PR-C is intentionally narrow:
    #   * No facing.
    #   * No AoO trigger from leaving threatened squares (PR-D).
    #   * No pathfinding around obstacles (no obstacles modeled yet).
    #   * No diagonal-cost asymmetry (Chebyshev distance — every diagonal
    #     counts as 1 square — diverges from canonical PF1e but is the
    #     simplest correct rule until PR-D needs more.)
    def resolve_move
      x = @params[:x]
      y = @params[:y]
      raise Error.new('x and y are required', code: :missing_coordinates) if x.nil? || y.nil?

      target_x = x.to_i
      target_y = y.to_i

      origin = Combat::Positions.player_position(@adventure)
      raise Error.new('player has no canonical position on the battlefield', code: :missing_player_position) unless origin&.coordinates_present?

      if origin.x.to_i == target_x && origin.y.to_i == target_y
        raise Error.new('player is already on that square', code: :no_op_move)
      end

      raise Error.new('target square is occupied', code: :square_occupied) if Combat::Positions.occupied?(@adventure, x: target_x, y: target_y, except_token_id: Combat::Positions::PLAYER_TOKEN_ID)

      distance = [(origin.x.to_i - target_x).abs, (origin.y.to_i - target_y).abs].max
      speed_squares = Combat::Positions.speed_squares_for(@sheet)
      raise Error.new("target is #{distance} squares away — speed allows up to #{speed_squares}", code: :out_of_reach) if distance > speed_squares

      delta, mode = movement_cost_delta(distance)
      provoke_aoo = mode == 'move'
      aoo_outcomes = provoke_aoo ? resolve_aoo_against_player(origin) : []

      battlefield = nil
      ApplicationRecord.transaction do
        battlefield = Combat::Positions.move_player_token!(@adventure, x: target_x, y: target_y)
        decrement_action_economy_with_delta!(delta, label: "#{mode} (#{distance} squares)")
      end

      payload = {
        kind: 'move',
        from: { x: origin.x.to_i, y: origin.y.to_i },
        to: { x: target_x, y: target_y },
        distance_squares: distance,
        movement_mode: mode,
        battlefield_version: battlefield&.version,
        attacks_of_opportunity: aoo_outcomes.map(&:to_h),
        message: build_move_message(distance, mode, aoo_outcomes)
      }
      log_action_event!(payload)
      { status: :resolved, result: payload }
    end

    # 5-foot step does NOT provoke; standard move does. PR-D models the
    # textbook PF1e rule: any combatant that threatens the square the
    # mover *leaves* gets one free swing. We resolve those AoOs server-
    # side regardless of dice strategy — the player doesn't roll for
    # NPC reactions.
    def resolve_aoo_against_player(origin)
      others = Combat::Positions.for_adventure(@adventure).reject { |p| p.token_id == Combat::Positions::PLAYER_TOKEN_ID }
      threats = Combat::Rules.aoo_threats_against(mover: origin, mover_from: origin, others: others)
      return [] if threats.empty?

      threats.filter_map do |threat|
        creature = creature_for_position(threat.position)
        next unless creature

        next if creature.hp.to_i <= 0

        Combat::NpcAttackResolver.call(attacker: creature, target_sheet: @sheet, target_kind: :player)
      end
    end

    def creature_for_position(position)
      sid = position.creature_sheet_id
      return nil if sid.blank?

      @adventure.creature_sheets.find_by(id: sid.to_i)
    end

    def build_move_message(distance, mode, aoo_outcomes)
      base = "Moved #{distance} squares (#{mode})."
      return base if aoo_outcomes.empty?

      hit_count = aoo_outcomes.count(&:hit)
      "#{base} Provoked #{aoo_outcomes.size} AoO#{aoo_outcomes.size == 1 ? '' : 's'} (#{hit_count} hit)."
    end

    # 5-foot step is one square when a move action is still available AND
    # standard hasn't been claimed via full_round; otherwise spend the move
    # action proper. Both are subject to the speed cap above.
    def movement_cost_delta(distance)
      econ = (@adventure.combat_context || {})['action_economy'] || {}
      can_5ft_step = distance == 1 && econ['standard_available'] == true && econ['full_round_claimed'] != true && econ['move_available'] == true

      if can_5ft_step
        # 5-ft step traditionally consumes neither standard nor move slots,
        # but for the simplified PR-C economy we still spend the move slot
        # so the chip surfaces a cost. Refine in PR-D once AoO + true 5-ft
        # step semantics matter.
        [{ 'spend_move' => true }, '5-foot step']
      elsif econ['move_available'] == true
        [{ 'spend_move' => true }, 'move']
      else
        raise Error.new('no move action available this turn', code: :no_move_available)
      end
    end

    def decrement_action_economy_with_delta!(delta, label:)
      ctx = @adventure.combat_context.deep_dup.deep_stringify_keys
      ctx['action_economy'] = DungeonMaster::Battlefield::ActionEconomy.apply_delta!(ctx['action_economy'], delta)
      @adventure.update!(combat_context: ctx)
    rescue ArgumentError => e
      raise Error.new("action economy refused #{label}: #{e.message}", code: :action_economy_refused)
    end

    # ── End turn ────────────────────────────────────────────────────────

    # PR-B intentionally skips NPC actions on end-turn; the deterministic
    # NPC turn engine (Combat::NpcTurn) lands in PR-F. Until then we
    # cycle the round counter, reseed the player's action economy, and
    # log a row noting that NPCs were skipped so play history makes sense.
    def resolve_end_turn
      ctx = @adventure.combat_context.deep_dup.deep_stringify_keys
      next_round = ctx['round'].to_i.then { |r| (r < 1 ? 1 : r) + 1 }

      ApplicationRecord.transaction do
        ctx['round'] = next_round
        ctx['current_turn'] = PLAYER_NAME
        ctx['action_economy'] = DungeonMaster::Battlefield::ActionEconomy.build_for_turn_holder(
          PLAYER_NAME, combat_ctx: ctx
        )
        @adventure.update!(combat_context: ctx)
      end

      payload = {
        kind: 'end_turn',
        round_advanced_to: next_round,
        npc_actions_skipped: true,
        message: "Turn ended. Round #{next_round} begins. (NPC actions are deterministic in PR-F; none ran this round.)"
      }
      log_action_event!(payload)
      { status: :resolved, result: payload }
    end

    # ── Validation ──────────────────────────────────────────────────────

    def ensure_combat_active!
      return if @adventure.combat_active?

      raise Error.new('combat is not active', code: :combat_not_active)
    end

    def ensure_player_turn!
      ctx = @adventure.combat_context || {}
      turn = ctx['current_turn'].to_s
      return if turn == PLAYER_NAME

      raise Error.new("not the player's turn (current: #{turn.presence || 'unknown'})", code: :not_player_turn)
    end

    def ensure_supported_kind!
      kind = @params[:kind].to_s
      return if SUPPORTED_KINDS.include?(kind)

      raise Error.new("unsupported combat action kind: #{kind.inspect}", code: :unsupported_kind)
    end

    # ── Lookups ─────────────────────────────────────────────────────────

    def lookup_attack_option!
      option_id = @params[:attack_option_id].to_s
      raise Error.new('attack_option_id is required', code: :missing_attack_option_id) if option_id.empty?

      DungeonMaster::Combat::AttackOptionBuilder.resolve_option_id!(
        sheet: @sheet, adventure: @adventure, option_id: option_id
      )
    rescue DungeonMaster::CombatMechanicResolutionError => e
      raise Error.new(e.message, code: e.code || :unknown_attack_option)
    end

    # Returns [:player|:creature, sheet, name].
    def lookup_target!
      target_id = @params[:target_creature_sheet_id]
      raise Error.new('target_creature_sheet_id is required', code: :missing_target) if target_id.blank?

      creature = @adventure.creature_sheets.find_by(id: target_id.to_i)
      raise Error.new("creature not found: id=#{target_id}", code: :target_not_found) unless creature

      raise Error.new("target is already down: #{creature.name}", code: :target_down) if creature.hp.to_i <= 0

      [creature, creature.name]
    end

    # ── Math ────────────────────────────────────────────────────────────

    def attack_bonus_for(option)
      stats = @sheet.derived_stats || {}
      key = ranged_mode?(option[:attack_mode]) ? 'ranged_attack' : 'melee_attack'
      bonus = stats[key] || stats[key.to_sym]
      raise Error.new("missing #{key} on player sheet", code: :missing_attack_bonus) if bonus.nil?

      bonus.to_i
    end

    def defense_dc_for(target, option)
      creature = target.first
      stats = creature.derived_stats || {}
      stat_key = DEFENSE_KIND_TO_STAT[option[:defense_kind].to_s] || 'ac'
      dc = stats[stat_key] || stats[stat_key.to_sym] || stats['ac'] || stats[:ac]
      raise Error.new("missing #{stat_key} on target derived_stats", code: :missing_defense_stat) if dc.nil?

      dc.to_i
    end

    def ranged_mode?(attack_mode)
      attack_mode.to_s.start_with?('ranged')
    end

    def damage_ability_bonus(option)
      return 0 if option[:source_type].to_s == 'spell'

      return 0 if ranged_mode?(option[:attack_mode])

      mods = (@sheet.derived_stats || {})['mods'] || {}
      mods['strength'].to_i
    end

    # ── Dice ────────────────────────────────────────────────────────────

    def resolve_attack_dice(option:, attack_bonus:, defense_dc:)
      natural = if @submitted_dice
                  validate_natural!(@submitted_dice[:attack_natural], 1..20, 'attack_natural')
                else
                  DungeonMaster::Rolls::CombatDice.roll_d20
                end
      total = natural + attack_bonus
      hit = total >= defense_dc || natural == 20
      hit = false if natural == 1
      [natural, total, hit]
    end

    def resolve_damage_dice(option:, hit:)
      return [nil, nil] unless hit

      ability = damage_ability_bonus(option)
      base = if @submitted_dice
               validate_natural!(@submitted_dice[:damage_natural], 1..1000, 'damage_natural')
             else
               DungeonMaster::Rolls::CombatDice.roll_damage_expression(option[:damage].to_s)
             end
      total = [base + ability, 1].max
      [base, total]
    end

    def validate_natural!(value, range, label)
      n = value.to_i
      raise Error.new("invalid #{label}: #{value.inspect}", code: :invalid_dice_submission) unless range.cover?(n)

      n
    end

    # ── Resolution side effects ─────────────────────────────────────────

    def apply_resolution(option:, target:, attack_bonus:, defense_dc:, attack_natural:,
                         attack_total:, hit:, damage_natural:, damage_total:, situational: zero_situational)
      creature, target_name = target
      hp_before = creature.hp.to_i
      hp_after = hp_before
      target_dropped = false

      ApplicationRecord.transaction do
        if hit && damage_total
          hp_after = (hp_before - damage_total).clamp(0, creature.max_hp.to_i)
          creature.update!(hp: hp_after)
          target_dropped = hp_after <= 0
        end

        decrement_action_economy!(option)
      end

      payload = build_resolution_payload(
        option: option, target_name: target_name, attack_bonus: attack_bonus,
        defense_dc: defense_dc, attack_natural: attack_natural, attack_total: attack_total,
        hit: hit, damage_natural: damage_natural, damage_total: damage_total,
        hp_before: hp_before, hp_after: hp_after, target_dropped: target_dropped,
        situational: situational
      )

      log_action_event!(payload)

      { status: :resolved, result: payload }
    end

    def decrement_action_economy!(option)
      ctx = @adventure.combat_context.deep_dup.deep_stringify_keys
      delta = action_cost_delta(option)
      ctx['action_economy'] = DungeonMaster::Battlefield::ActionEconomy.apply_delta!(ctx['action_economy'], delta)
      @adventure.update!(combat_context: ctx)
    rescue ArgumentError => e
      raise Error.new("action economy refused the cost: #{e.message}", code: :action_economy_refused)
    end

    def action_cost_delta(option)
      case option[:action_cost].to_s
      when 'full_round' then { 'spend_full_round' => true }
      when 'move'       then { 'spend_move' => true }
      when 'swift'      then { 'spend_swift' => true }
      else                   { 'spend_standard' => true }
      end
    end

    def build_resolution_payload(option:, target_name:, attack_bonus:, defense_dc:,
                                 attack_natural:, attack_total:, hit:, damage_natural:,
                                 damage_total:, hp_before:, hp_after:, target_dropped:,
                                 situational: zero_situational)
      {
        kind: 'attack',
        attack_option_id: option[:id].to_s,
        attack_label: option[:label].to_s,
        target_name: target_name,
        attack_mode: option[:attack_mode],
        defense_kind: option[:defense_kind],
        attack_bonus: attack_bonus,
        attack_natural: attack_natural,
        attack_total: attack_total,
        defense_dc: defense_dc,
        crit_threat: attack_natural == 20,
        natural_one: attack_natural == 1,
        hit: hit,
        damage_expression: option[:damage],
        damage_type: option[:damage_type],
        damage_natural: damage_natural,
        damage_total: damage_total,
        target_hp_before: hp_before,
        target_hp_after: hp_after,
        target_dropped: target_dropped,
        flanking: situational[:flanking],
        flanking_bonus: situational[:flanking_bonus],
        cover_bonus: situational[:cover_bonus],
        message: human_message(option: option, target_name: target_name, hit: hit,
                               attack_total: attack_total, defense_dc: defense_dc,
                               damage_total: damage_total, target_dropped: target_dropped,
                               situational: situational)
      }
    end

    def human_message(option:, target_name:, hit:, attack_total:, defense_dc:,
                      damage_total:, target_dropped:, situational: zero_situational)
      verb = hit ? 'hits' : 'misses'
      tags = []
      tags << '+2 flanking' if situational[:flanking]
      tags << '+4 cover' if situational[:cover_bonus].to_i.positive?
      tag_str = tags.any? ? " (#{tags.join(', ')})" : ''
      core = "#{option[:label]} vs #{target_name}: #{attack_total} vs AC #{defense_dc} — #{verb}#{tag_str}"
      return "#{core}." unless hit && damage_total

      damage_phrase = "#{damage_total}#{" #{option[:damage_type]}" if option[:damage_type].present?}"
      tail = target_dropped ? ", dropping #{target_name}" : ''
      "#{core} for #{damage_phrase} damage#{tail}."
    end

    def log_action_event!(payload)
      PlayLog.create!(
        adventure: @adventure,
        event_type: 'combat_action',
        prompt_summary: payload[:message].to_s.truncate(200),
        parsed_response: payload.to_json,
        status: 'pipeline_event',
        app_version: defined?(APP_VERSION) ? APP_VERSION : nil
      )
    rescue StandardError => e
      Rails.logger.warn("[PlayerActionResolver] play_log persist failed: #{e.message}")
    end

    def awaiting_player_dice(option:, target:, attack_bonus:, defense_dc:, situational: zero_situational)
      _creature, target_name = target
      damage_ability = damage_ability_bonus(option)
      {
        status: :awaiting_player_dice,
        request: {
          kind: 'attack',
          attack_option_id: option[:id].to_s,
          attack_label: option[:label].to_s,
          target_name: target_name,
          target_creature_sheet_id: target.first.id,
          attack_bonus: attack_bonus,
          defense_dc: defense_dc,
          defense_kind: option[:defense_kind],
          damage_expression: option[:damage],
          damage_type: option[:damage_type],
          damage_ability_bonus: damage_ability,
          flanking: situational[:flanking],
          flanking_bonus: situational[:flanking_bonus],
          cover_bonus: situational[:cover_bonus]
        }
      }
    end

    def client_dice?
      @user&.combat_dice_strategy.to_s == 'client'
    end
  end
end
