# frozen_string_literal: true

module DungeonMaster
  module WorldTurn
    # Resolves one NPC's structured npc_action JSON: flee / surrender / attack + {Rolls::CombatDice}.
    module NpcActionResolver
      class << self
        PLAYER = Utilities::CombatTurnCalculator::PLAYER_NAME

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
            res = resolve_attack(npc, parsed, combat_ctx, player_sheet, adventure)
            lines.concat(res[:lines])
            npc_muts.concat(res[:npc_muts])
            player_hp += res[:player_hp_delta].to_i
          else
            lines << "#{npc.name} takes no decisive action."
          end

          { lines: lines, npc_muts: npc_muts, player_hp_delta: player_hp }
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
            atk = Rolls::CombatDice.d20_attack_vs_ac(modifier: mod, ac: ac)
            if atk[:hit]
              dmg = Rolls::CombatDice.roll_damage_expression(dice)
              lines << "#{npc.name} attacks Player: #{atk[:d20]}+#{mod}=#{atk[:total]} vs AC #{ac} — HIT for #{dmg}."
              player_hp -= dmg
            else
              lines << "#{npc.name} attacks Player: #{atk[:d20]}+#{mod}=#{atk[:total]} vs AC #{ac} — miss."
            end
          else
            ac = ParticipantLookup.ac_for_name(target, combat_ctx: combat_ctx,
              player_sheet: player_sheet, adventure: adventure)
            if ac.nil?
              lines << "#{npc.name} attacks #{target} — invalid target."
            else
              atk = Rolls::CombatDice.d20_attack_vs_ac(modifier: mod, ac: ac)
              if atk[:hit]
                dmg = Rolls::CombatDice.roll_damage_expression(dice)
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
      end
    end
  end
end
