# frozen_string_literal: true

module Combat
  module WorldTurn
    module NpcActionResolver
      class << self
        PLAYER = Combat::TurnCalculator::PLAYER_NAME # canonical name — see CombatTurnCalculator::PLAYER_NAME

        # @return [Hash] :lines (Array<String>), :npc_muts, :player_hp_delta
        def resolve(npc:, parsed:, combat_ctx:, player_sheet:, adventure:)
          action = parsed[:action].to_s.downcase
          lines = []
          npc_muts = []
          player_hp = 0

          case action
          when "flee"
            lines << "#{npc.name} disengages and flees."
            npc_muts << { creature_sheet_id: npc.creature_sheet_id, name: npc.name, conditions_add: ["fled"] }
          when "surrender"
            lines << "#{npc.name} surrenders."
            npc_muts << { creature_sheet_id: npc.creature_sheet_id, name: npc.name, conditions_add: ["surrendered"] }
          when "attack"
            attack_resolution = resolve_attack(npc, parsed, combat_ctx, player_sheet, adventure)
            lines.concat(attack_resolution[:lines])
            npc_muts.concat(attack_resolution[:npc_muts])
            player_hp += attack_resolution[:player_hp_delta].to_i
          else
            lines << "#{npc.name} takes no decisive action."
          end

          bf_patches = Array(parsed[:battlefield_patches]).map { |p| p.is_a?(Hash) ? p.deep_stringify_keys : p }

          NpcActionResult.new(
            lines: lines,
            npc_mutations: npc_muts,
            player_hp_delta: player_hp,
            battlefield_patches: bf_patches
          ).to_h
        end

        private

        def resolve_attack(npc, parsed, combat_ctx, player_sheet, adventure)
          lines = []
          npc_muts = []
          player_hp = 0

          target = parsed[:target].to_s.strip
          target = PLAYER if target.blank? || target.casecmp("player").zero?
          mod = parsed[:attack_modifier].to_i
          dice = parsed[:damage_dice].presence || "1d4"

          if target == PLAYER
            ac = player_sheet.derived_stats.fetch("ac").to_i
            roll = attack_roll_vs_ac(mod:, dice:, ac:)
            if roll[:atk][:hit]
              dmg = roll[:damage]
              lines << "#{npc.name} attacks Player: #{roll[:atk][:d20]}+#{mod}=#{roll[:atk][:total]} vs AC #{ac} — HIT for #{dmg}."
              player_hp -= dmg
            else
              lines << "#{npc.name} attacks Player: #{roll[:atk][:d20]}+#{mod}=#{roll[:atk][:total]} vs AC #{ac} — miss."
            end
          else
            ac = ParticipantLookup.ac_for_name(target, combat_ctx: combat_ctx,
              player_sheet: player_sheet, adventure: adventure)
            if ac.nil?
              lines << "#{npc.name} attacks #{target} — invalid target."
            else
              roll = attack_roll_vs_ac(mod:, dice:, ac: ac)
              if roll[:atk][:hit]
                dmg = roll[:damage]
                lines << "#{npc.name} attacks #{target}: hit for #{dmg}."
                tid = ParticipantLookup.creature_sheet_id_for_name(target, combat_ctx)
                npc_muts << { creature_sheet_id: tid, name: target, hp_change: -dmg } if tid.present?
              else
                lines << "#{npc.name} attacks #{target}: miss."
              end
            end
          end

          { lines: lines, npc_muts: npc_muts, player_hp_delta: player_hp }
        end

        # @return [Hash] :atk => d20_attack_vs_ac result, :damage => Integer or nil if miss
        def attack_roll_vs_ac(mod:, dice:, ac:)
          atk = Combat::Dice.d20_attack_vs_ac(modifier: mod, ac: ac)
          damage = atk[:hit] ? Combat::Dice.roll_damage_expression(dice) : nil
          { atk: atk, damage: damage }
        end
      end
    end
  end
end
