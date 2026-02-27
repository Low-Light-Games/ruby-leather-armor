# frozen_string_literal: true

module DungeonMasterLight
  # Manages the full combat encounter lifecycle for the Light DM system.
  # Runs entirely in-app: creates encounters, manages the grid, resolves
  # turns, and uses EnemyAiService minimally for NPC action selection.
  #
  # "Hijacks" the adventure chat by posting messages through adventure_messages,
  # so the player experiences combat as part of the normal conversation flow.
  class CombatService
    SQUARES_PER_FOOT = 5

    def initialize(adventure, log:)
      @adventure = adventure
      @log = log
    end

    # ----------------------------------------------------------------
    # Encounter lifecycle
    # ----------------------------------------------------------------

    # Start a new combat encounter with the given creature sheets as enemies.
    #
    # @param creature_sheets [Array<CreatureSheet>] enemy combatants
    # @return [Encounter]
    def start_encounter(creature_sheets)
      encounter = create_encounter(creature_sheets)
      roll_initiative(encounter)
      encounter.update!(status: "active", round_number: 1)

      post_combat_start(encounter)
      process_until_player_turn(encounter)

      encounter
    end

    # Process a player's combat action.
    #
    # @param encounter [Encounter]
    # @param action [String] what the player wants to do
    # @return [Hash] { messages: [...], encounter_ended: bool }
    def process_player_action(encounter, action)
      participant = current_player_participant(encounter)
      return { error: "Not the player's turn" } unless participant&.player?

      result = resolve_player_action(encounter, participant, action)

      encounter.advance_turn!
      check_end_conditions(encounter)

      unless encounter.completed?
        process_until_player_turn(encounter)
        check_end_conditions(encounter)
      end

      {
        result: result,
        encounter_ended: encounter.completed?,
        narrative_summary: encounter.completed? ? encounter.narrative_summary : nil
      }
    end

    # End encounter early (flee, surrender, etc.).
    def end_encounter(encounter, reason: "ended")
      summary = build_narrative_summary(encounter, reason)
      encounter.update!(status: "completed", narrative_summary: summary)

      persist_message(
        "Combat has ended. #{reason.capitalize}.",
        message_type: "narrative"
      )

      summary
    end

    # ----------------------------------------------------------------
    # Encounter setup
    # ----------------------------------------------------------------

    private

    def create_encounter(creature_sheets)
      grid = generate_grid(creature_sheets.size)

      encounter = @adventure.encounters.create!(
        status: "pending",
        grid_width: grid[:width],
        grid_height: grid[:height],
        terrain_data: grid[:terrain]
      )

      player_sheet = @adventure.adventure_sheets.first
      if player_sheet
        encounter.encounter_participants.create!(
          adventure_sheet: player_sheet,
          team: "player",
          position_x: grid[:player_start][0],
          position_y: grid[:player_start][1],
          current_hp: player_sheet.hp
        )
      end

      creature_sheets.each_with_index do |cs, i|
        cs.recompute_derived_stats! if cs.derived_stats.blank?
        max_hp = cs.derived_stats["max_hp"] || cs.max_hp
        max_hp = [max_hp, 1].max
        cs.update!(hp: max_hp, max_hp: max_hp) if cs.max_hp == 0

        pos = grid[:enemy_starts][i] || [grid[:width] - 2, (grid[:height] / 2) + i]
        encounter.encounter_participants.create!(
          creature_sheet: cs,
          team: "enemy",
          position_x: pos[0],
          position_y: pos[1],
          current_hp: cs.max_hp
        )
      end

      @log.dm_log!("Encounter created: #{encounter.id}, grid #{grid[:width]}x#{grid[:height]}, " \
                    "#{creature_sheets.size} enemies")
      encounter
    end

    def generate_grid(enemy_count)
      width = [8, 6 + enemy_count * 2].min
      height = [8, 4 + enemy_count * 2].min

      terrain = {}
      # Add some random difficult terrain
      (rand(1..3)).times do
        x = rand(2..width - 3)
        y = rand(1..height - 2)
        terrain["#{x},#{y}"] = "difficult"
      end

      player_start = [1, height / 2]

      enemy_starts = enemy_count.times.map do |i|
        [width - 2, [1 + i * 2, height - 2].min]
      end

      { width: width, height: height, terrain: terrain,
        player_start: player_start, enemy_starts: enemy_starts }
    end

    def roll_initiative(encounter)
      encounter.encounter_participants.each do |p|
        ds = if p.adventure_sheet
               p.adventure_sheet.derived_stats || {}
             else
               p.creature_sheet&.derived_stats || {}
             end

        init_mod = ds["initiative"] || 0
        roll = rand(1..20)
        p.update!(initiative: roll + init_mod)
      end

      @log.dm_log!("Initiative rolled: " +
        encounter.encounter_participants.order(initiative: :desc).map { |p|
          "#{p.name} (#{p.initiative})"
        }.join(", "))
    end

    # ----------------------------------------------------------------
    # Turn processing
    # ----------------------------------------------------------------

    def process_until_player_turn(encounter)
      encounter.reload
      safety = 0

      loop do
        safety += 1
        break if safety > 50
        break if encounter.completed?

        current = current_participant(encounter)
        break unless current
        break if current.player?
        break unless current.alive?

        process_enemy_turn(encounter, current)
        encounter.advance_turn!
        encounter.reload

        check_end_conditions(encounter)
        break if encounter.completed?
      end
    end

    def process_enemy_turn(encounter, participant)
      creature = participant.creature_sheet
      return unless creature

      available_actions = build_available_actions(encounter, participant)
      chosen = pick_enemy_action(creature, available_actions, encounter, participant)

      resolve_enemy_action(encounter, participant, chosen)
    end

    def build_available_actions(encounter, participant)
      creature = participant.creature_sheet
      ds = creature.derived_stats || {}
      speed_squares = (ds["speed"] || 30) / SQUARES_PER_FOOT
      actions = []

      player = encounter.encounter_participants.find_by(team: "player", is_active: true)
      return actions unless player

      dist = participant.distance_to(player)
      dist_squares = (dist / SQUARES_PER_FOOT).round

      # Melee attack (if adjacent or within reach)
      if dist_squares <= 1
        melee_mod = ds["melee_attack"] || 0
        weapons = creature.equipped_weapons.presence || [{ "name" => "unarmed strike", "damage" => "1d3" }]
        weapons.each do |w|
          actions << {
            type: "melee_attack",
            description: "Attack #{player.name} with #{w['name']} (melee, +#{melee_mod}, #{w['damage'] || '1d4'} damage)",
            target: player,
            weapon: w,
            attack_mod: melee_mod
          }
        end
      end

      # Move and melee (if within movement + reach range)
      if dist_squares > 1 && dist_squares <= speed_squares + 1
        melee_mod = ds["melee_attack"] || 0
        weapon = (creature.equipped_weapons.presence || [{ "name" => "unarmed strike", "damage" => "1d3" }]).first
        actions << {
          type: "move_and_attack",
          description: "Move toward #{player.name} and attack with #{weapon['name']}",
          target: player,
          weapon: weapon,
          attack_mod: melee_mod
        }
      end

      # Ranged attack (if weapon available and not adjacent)
      ranged_weapons = (creature.equipped_weapons || []).select { |w| w["type"] == "ranged" }
      ranged_weapons.each do |w|
        ranged_mod = ds["ranged_attack"] || 0
        range = w["range"] || 30
        if dist <= range
          actions << {
            type: "ranged_attack",
            description: "Shoot #{player.name} with #{w['name']} (ranged, +#{ranged_mod}, #{w['damage'] || '1d6'}, distance: #{dist.round}ft)",
            target: player,
            weapon: w,
            attack_mod: ranged_mod
          }
        end
      end

      # Move toward player (if too far to attack)
      if dist_squares > 1
        actions << {
          type: "move",
          description: "Move toward #{player.name} (close distance)",
          target: player
        }
      end

      # Retreat
      actions << {
        type: "retreat",
        description: "Retreat away from combat"
      }

      actions
    end

    def pick_enemy_action(creature, available_actions, encounter, participant)
      return available_actions.first if available_actions.size <= 1

      enemy_ai = DungeonMasterLight::EnemyAiService.new(
        DmConfig.instance,
        DungeonMaster::Logging.new(adventure: @adventure, user: nil, dm_service: "light")
      )

      enemy_ai.choose_action(creature, available_actions, encounter, participant)
    end

    def resolve_enemy_action(encounter, participant, action)
      return unless action

      creature = participant.creature_sheet
      result_text = case action[:type]
      when "melee_attack", "ranged_attack"
        resolve_attack(participant, action)
      when "move_and_attack"
        move_toward(participant, action[:target])
        resolve_attack(participant, action)
      when "move"
        move_toward(participant, action[:target])
        "#{creature.name} moves closer."
      when "retreat"
        move_away(participant, action[:target] || encounter.encounter_participants.find_by(team: "player"))
        "#{creature.name} retreats."
      else
        "#{creature.name} hesitates."
      end

      persist_message(result_text, message_type: "narrative", role: "dm") if result_text
    end

    def resolve_attack(attacker_participant, action)
      creature = attacker_participant.creature_sheet
      target = action[:target]
      return "#{creature.name} swings at nothing." unless target&.alive?

      attack_roll = rand(1..20)
      attack_mod = action[:attack_mod] || 0
      total_attack = attack_roll + attack_mod

      target_sheet = target.adventure_sheet || target.creature_sheet
      target_ac = target_sheet&.derived_stats&.dig("ac") || 10

      if attack_roll == 1
        "#{creature.name} attacks #{target.name} with #{action[:weapon]['name']}... " \
          "Natural 1! A critical miss."
      elsif attack_roll == 20 || total_attack >= target_ac
        damage = roll_damage(action[:weapon])
        target.update!(current_hp: [target.current_hp - damage, 0].max)

        if target.adventure_sheet
          target.adventure_sheet.update!(hp: target.current_hp)
        end

        hit_text = attack_roll == 20 ? "Critical threat! " : ""
        "#{creature.name} attacks #{target.name} with #{action[:weapon]['name']} " \
          "(#{attack_roll}+#{attack_mod}=#{total_attack} vs AC #{target_ac}). " \
          "#{hit_text}Hit for #{damage} damage! (#{target.name}: #{target.current_hp} HP remaining)"
      else
        "#{creature.name} attacks #{target.name} with #{action[:weapon]['name']} " \
          "(#{attack_roll}+#{attack_mod}=#{total_attack} vs AC #{target_ac}). Miss!"
      end
    end

    # ----------------------------------------------------------------
    # Player action resolution
    # ----------------------------------------------------------------

    def resolve_player_action(encounter, participant, action_text)
      player_sheet = participant.adventure_sheet
      ds = player_sheet&.derived_stats || {}

      enemies = encounter.encounter_participants.where(team: "enemy", is_active: true)
      nearest_enemy = enemies.min_by { |e| participant.distance_to(e) }

      action_lower = action_text.downcase

      if action_lower.include?("attack") || action_lower.include?("hit") || action_lower.include?("strike")
        resolve_player_attack(encounter, participant, nearest_enemy, ds, action_text)
      elsif action_lower.include?("move") || action_lower.include?("approach") || action_lower.include?("advance")
        if nearest_enemy
          move_toward(participant, nearest_enemy)
          "You move closer to #{nearest_enemy.name}."
        else
          "There's nowhere meaningful to move."
        end
      elsif action_lower.include?("flee") || action_lower.include?("run") || action_lower.include?("retreat")
        end_encounter(encounter, reason: "The player fled the battle")
        "You flee from combat!"
      else
        persist_message(
          "In combat, you can: attack, move, flee, or use an item/spell. What do you do?",
          message_type: "narrative",
          role: "dm"
        )
        "Awaiting valid combat action."
      end
    end

    def resolve_player_attack(encounter, participant, target, ds, action_text)
      unless target&.alive?
        return "There are no enemies left to attack!"
      end

      dist = participant.distance_to(target)
      melee_range = dist <= SQUARES_PER_FOOT * 1.5 # adjacent

      if melee_range
        attack_mod = ds["melee_attack"] || 0
        weapon_name = "weapon"
      else
        attack_mod = ds["ranged_attack"] || 0
        weapon_name = "ranged weapon"
      end

      persist_message(
        "You attack #{target.name} with your #{weapon_name}. Roll to attack! " \
          "(Your attack modifier: +#{attack_mod}, target AC: #{target_ac(target)})",
        message_type: "roll_request",
        role: "dm",
        metadata: {
          roll_request: {
            type: "attack",
            dc: target_ac(target),
            description: "Attack #{target.name}"
          }
        }
      )

      "Roll requested for attack against #{target.name}."
    end

    def target_ac(participant)
      sheet = participant.adventure_sheet || participant.creature_sheet
      sheet&.derived_stats&.dig("ac") || 10
    end

    # ----------------------------------------------------------------
    # Movement helpers
    # ----------------------------------------------------------------

    def move_toward(mover, target)
      return unless target

      speed = speed_in_squares(mover)
      dx = target.position_x - mover.position_x
      dy = target.position_y - mover.position_y
      dist = Math.sqrt(dx**2 + dy**2)
      return if dist < 1

      ratio = [speed.to_f / dist, 1.0].min
      new_x = (mover.position_x + dx * ratio).round
      new_y = (mover.position_y + dy * ratio).round

      # Don't land on target's exact square
      if new_x == target.position_x && new_y == target.position_y
        new_x = mover.position_x + ((dx > 0 ? 1 : -1) * [speed - 1, 0].max).clamp(-speed, speed)
      end

      mover.update!(position_x: new_x.clamp(0, 99), position_y: new_y.clamp(0, 99))
    end

    def move_away(mover, target)
      return unless target

      speed = speed_in_squares(mover)
      dx = mover.position_x - target.position_x
      dy = mover.position_y - target.position_y
      dist = Math.sqrt(dx**2 + dy**2)

      if dist > 0
        ratio = speed.to_f / dist
        new_x = (mover.position_x + dx * ratio).round
        new_y = (mover.position_y + dy * ratio).round
      else
        new_x = mover.position_x + speed
        new_y = mover.position_y
      end

      mover.update!(position_x: new_x.clamp(0, 99), position_y: new_y.clamp(0, 99))
    end

    def speed_in_squares(participant)
      sheet = participant.adventure_sheet || participant.creature_sheet
      speed_ft = sheet&.derived_stats&.dig("speed") || 30
      speed_ft / SQUARES_PER_FOOT
    end

    # ----------------------------------------------------------------
    # End conditions
    # ----------------------------------------------------------------

    def check_end_conditions(encounter)
      return if encounter.completed?

      encounter.encounter_participants.where("current_hp <= 0 AND is_active = true").find_each do |p|
        p.update!(is_active: false)
      end

      enemies_alive = encounter.encounter_participants.where(team: "enemy", is_active: true).exists?
      player_alive = encounter.encounter_participants.where(team: "player", is_active: true).where("current_hp > 0").exists?

      if !enemies_alive
        end_encounter(encounter, reason: "All enemies defeated! Victory!")
      elsif !player_alive
        end_encounter(encounter, reason: "The player has fallen...")
      end
    end

    # ----------------------------------------------------------------
    # Helpers
    # ----------------------------------------------------------------

    def roll_damage(weapon)
      dice = weapon&.dig("damage") || weapon&.dig("damage_dice") || "1d4"
      match = dice.match(/(\d+)d(\d+)/)
      return rand(1..4) unless match

      count = match[1].to_i
      sides = match[2].to_i
      total = count.times.sum { rand(1..sides) }

      str_bonus = weapon.dig("strength_bonus") || 0
      [total + str_bonus, 1].max
    end

    def build_narrative_summary(encounter, reason)
      parts = ["Combat encounter (#{encounter.round_number} rounds). #{reason}."]

      encounter.encounter_participants.each do |p|
        status = p.alive? ? "alive (#{p.current_hp} HP)" : "defeated"
        parts << "#{p.name} (#{p.team}): #{status}"
      end

      parts.join(" ")
    end

    def current_participant(encounter)
      encounter.current_participant
    end

    def current_player_participant(encounter)
      p = current_participant(encounter)
      p&.player? ? p : nil
    end

    def persist_message(content, message_type: "narrative", role: "dm", metadata: {})
      @adventure.adventure_messages.create!(
        role: role,
        content: content,
        message_type: message_type,
        metadata: metadata
      )
    end

    def post_combat_start(encounter)
      participants = encounter.encounter_participants.order(initiative: :desc)
      lines = ["**Combat begins!**", ""]
      lines << "Initiative order:"
      participants.each_with_index do |p, i|
        lines << "#{i + 1}. #{p.name} (#{p.team}) — Initiative #{p.initiative}, HP #{p.current_hp}"
      end
      lines << ""
      lines << "Grid: #{encounter.grid_width}x#{encounter.grid_height} squares (1 square = 5ft)"

      persist_message(lines.join("\n"), message_type: "narrative")
    end
  end
end
