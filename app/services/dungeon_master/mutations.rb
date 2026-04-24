# frozen_string_literal: true

module DungeonMaster
  # App-side game state logic: applies AI-determined mutations to player/NPC
  # sheets, resolves NPC dice rolls, and manages inventory changes.
  #
  # Creature creation (bestiary lookup, AI fallback, template) has been
  # extracted to DungeonMaster::CreatureFactory.
  module Mutations
    private

    def apply_mutations(mutations)
      return unless mutations.is_a?(Hash)

      mutations = mutations.deep_symbolize_keys
      apply_action_economy_delta_from_mutations!(mutations)
      apply_battlefield_patches_from_mutations!(mutations)
      apply_player_mutations(mutations[:player])
      apply_npc_mutations(mutations[:npcs])
      apply_inventory_mutations(mutations[:inventory])
      @on_sheet_update&.call
    end

    def apply_battlefield_patches_from_mutations!(mutations)
      patches = mutations[:battlefield_patches]
      return if patches.blank?

      Battlefield::ApplyPatches.call(adventure: @adventure, patches: patches, log: @log)
    end

    def apply_action_economy_delta_from_mutations!(mutations)
      delta = mutations[:action_economy_delta]
      return if delta.blank?

      ctx = @adventure.combat_context
      return unless ctx.is_a?(Hash)

      econ = ctx["action_economy"] || ctx[:action_economy]
      merged_econ = Battlefield::ActionEconomy.apply_delta!(econ, delta)
      new_ctx = ctx.deep_stringify_keys.merge("action_economy" => merged_econ)
      @adventure.update!(combat_context: new_ctx)
    rescue ArgumentError => e
      @log.log!(:warn, "[action_economy_delta] rejected: #{e.message}")
      raise AiError, "Invalid action economy for this turn: #{e.message}"
    end

    def resolve_npc_actions(npc_actions)
      return "(no NPC actions)" if npc_actions.blank?

      player_ac = @sheet.derived_stats.fetch("ac")
      results = npc_actions.map do |action|
        modifier = (action[:modifier] || 0).to_i
        atk = Rolls::CombatDice.d20_attack_vs_ac(modifier: modifier, ac: player_ac)
        "#{action[:actor]} #{action[:action]} -> rolled #{atk[:d20]} + #{modifier} = #{atk[:total]} " \
          "vs AC #{player_ac}: #{atk[:hit] ? 'HIT' : 'MISS'}"
      end

      results.join("\n")
    end

    def handle_new_creatures(creature_names)
      factory = CreatureFactory.new(@adventure,
        sheet:  @sheet,
        log:    @log,
        ai:     @ai,
        config: @config
      )

      CoercedMutationArray.coerce(creature_names, field: "new_creatures", log: @log).each do |name|
        factory.create_for_name(name)
      end
    rescue => e
      pipeline_error!("new_creatures", e)
    end

    # ── Player mutations ────────────────────────────────────────────

    def apply_player_mutations(player_muts)
      return unless player_muts && @sheet

      hp_change = player_muts[:hp_change]
      if hp_change.to_i != 0
        hp_floor = @config&.instant_death? ? 0 : -@sheet.constitution
        new_hp = (@sheet.hp + hp_change.to_i).clamp(hp_floor, @sheet.max_hp)
        @sheet.update!(hp: new_hp)
      end

      conditions_changed = apply_conditions(@sheet, player_muts[:conditions_add], player_muts[:conditions_remove])
      buff_lists         = BuffMutationLists.from_payload(
        buffs_add: player_muts[:buffs_add],
        buffs_remove: player_muts[:buffs_remove],
        log: @log
      )
      buffs_changed      = apply_buffs(@sheet, buff_lists)
      @sheet.recompute_derived_stats! if conditions_changed || buffs_changed
    end

    # ── Buff mutations ──────────────────────────────────────────────

    def apply_buffs(sheet, buff_lists)
      return false unless sheet.respond_to?(:active_buffs)

      rows = BuffMutationLists.active_buff_rows_from_sheet(sheet, log: @log)
      class_ability_ids = class_ability_ids_for_buff_adds(sheet, buff_lists.additions)

      changed = apply_buff_removals!(rows, buff_lists.removals)
      changed = apply_buff_additions!(rows, buff_lists.additions, sheet, class_ability_ids) || changed

      if changed
        sheet.update!(active_buffs: rows)
        summary = rows.map { |r| "#{r['source']}:#{r['source_type']}" }.join(", ")
        @log.log!(:info, "[buffs] updated active_buffs on sheet #{sheet.id}: #{summary}")
      end

      changed
    end

    # ── NPC mutations ───────────────────────────────────────────────

    def apply_npc_mutations(npc_muts)
      CoercedMutationArray.coerce(npc_muts, field: "npcs", log: @log).each do |npc_mut|
        npc_mut  = npc_mut.deep_symbolize_keys if npc_mut.is_a?(Hash)
        creature = resolve_creature_sheet_for_npc_mutation(npc_mut)
        next unless creature

        hp_change = npc_mut[:hp_change]
        if hp_change.to_i != 0
          new_hp = (creature.hp + hp_change.to_i).clamp(0, creature.max_hp)
          creature.update!(hp: new_hp)
        end

        attitude = npc_mut[:attitude_change]
        if attitude.is_a?(Hash)
          new_attitude = attitude[:to]
          creature.update!(attitude: new_attitude) if new_attitude && CreatureSheet::ATTITUDES.include?(new_attitude)
        end

        conditions_changed = apply_conditions(creature, npc_mut[:conditions_add], npc_mut[:conditions_remove])
        creature.recompute_derived_stats! if conditions_changed
      end
    end

    def resolve_creature_sheet_for_npc_mutation(npc_mut)
      sid = npc_mut[:creature_sheet_id]
      if sid.present?
        @adventure.creature_sheets.find_by(id: sid.to_i)
      elsif npc_mut[:name].present?
        @adventure.creature_sheets.find_by(name: npc_mut[:name].to_s)
      end
    end

    # ── Inventory mutations ─────────────────────────────────────────

    def apply_inventory_mutations(inventory_muts)
      return unless inventory_muts.present? && @sheet

      adventure_sheet = @adventure.adventure_sheets.first
      return unless adventure_sheet

      inventory_muts.each do |item_name, quantity|
        next unless item_name.present? && quantity.is_a?(Numeric) && quantity.to_i > 0

        add_inventory_item(adventure_sheet, item_name.to_s, quantity.to_i)
      end
    rescue => e
      pipeline_error!("inventory_mutations", e)
    end

    def add_inventory_item(adventure_sheet, item_name, quantity)
      item_def = find_or_create_item_definition(item_name)
      return unless item_def

      existing = adventure_sheet.adventure_sheet_items.find_by(item_definition_id: item_def.id)
      if existing
        new_quantity = existing.quantity + quantity
        existing.update!(quantity: new_quantity)
        @log.log!(:info, "Updated inventory: #{item_name} quantity #{existing.quantity - quantity} -> #{new_quantity}")
      else
        adventure_sheet.adventure_sheet_items.create!(
          item_definition_id: item_def.id,
          quantity: quantity,
          equipped: false
        )
        @log.log!(:info, "Added to inventory: #{item_name} (quantity: #{quantity})")
      end
    end

    def find_or_create_item_definition(item_name)
      normalized = item_name.downcase.strip
      ItemDefinition.find_by("LOWER(name) = ?", normalized) ||
        ItemDefinition.where("LOWER(name) LIKE ?", "%#{normalized}%").first ||
        create_generic_item_definition(item_name)
    end

    def create_generic_item_definition(item_name)
      item_id   = item_name.downcase.gsub(/[^a-z0-9]/, "_").gsub(/_+/, "_").gsub(/^_+|_+$/, "")
      counter   = 1
      base_id   = item_id
      item_id   = "#{base_id}_#{counter += 1}" while ItemDefinition.exists?(id: item_id)

      ItemDefinition.create!(
        id: item_id, name: item_name.titleize, item_type: "gear",
        category: nil, slot: "none", weight: 1, cost_gp: 0,
        armor_bonus: 0, shield_bonus: 0, max_dex_bonus: nil,
        armor_check_penalty: 0, arcane_spell_failure: 0,
        speed_30: nil, speed_20: nil, weapon_category: nil,
        weapon_type: nil, damage_dice: nil, critical_range: nil,
        damage_type: nil, range_increment: nil,
        summary: "A generic item acquired during adventure."
      )
    rescue ActiveRecord::RecordInvalid => e
      @log.log!(:error, "Failed to create item definition for '#{item_name}': #{e.message}")
      nil
    end

    def class_ability_ids_for_buff_adds(sheet, additions)
      wants = additions.any? { |row| row.is_a?(Hash) && row["source_type"].to_s == "class_ability" }
      return unless wants && sheet.respond_to?(:class_ability_definitions)

      sheet.class_ability_definitions.pluck(:id).map(&:to_s)
    end

    def apply_buff_removals!(rows, removals)
      changed = false
      removals.each do |raw_spec|
        changed = remove_buff_rows_for_spec!(rows, raw_spec) || changed
      end
      changed
    end

    def remove_buff_rows_for_spec!(rows, raw_spec)
      unless raw_spec.is_a?(Hash)
        @log&.log!(:warn, "[buffs] buffs_remove entry must be a Hash with id and source_type — skipped #{raw_spec.inspect}")
        return false
      end
      spec = raw_spec.deep_stringify_keys
      source_id = spec["id"].presence || spec["source"].presence
      source_type = spec["source_type"].presence
      unless source_id && source_type
        @log&.log!(:warn, "[buffs] buffs_remove entry missing id or source_type — skipped #{spec.inspect}")
        return false
      end
      before = rows.size
      rows.reject! do |row|
        next false unless row["source"].to_s == source_id.to_s

        stored_type = row["source_type"].to_s
        stored_type == source_type.to_s || stored_type.empty?
      end
      rows.size != before
    end

    def apply_buff_additions!(rows, additions, sheet, class_ability_ids)
      changed = false
      additions.each do |raw_row|
        changed = merge_resolved_buff_add_row!(rows, raw_row, sheet, class_ability_ids) || changed
      end
      changed
    end

    def merge_resolved_buff_add_row!(rows, raw_row, sheet, class_ability_ids)
      return false unless raw_row.is_a?(Hash)

      row = raw_row.deep_stringify_keys
      source_id = row["id"]
      source_type = row["source_type"]
      return false unless source_id.present? && source_type.present?

      resolved = Utilities::ActiveBuffResolver.resolve(
        source_id: source_id,
        source_type: source_type,
        adventure: @adventure,
        sheet: sheet,
        log: @log,
        class_ability_sheet_ids: class_ability_ids,
        buffs_add_entry: row
      )
      return false if resolved.empty?

      rows.reject! do |existing|
        next false unless existing["source"].to_s == source_id.to_s

        existing_type = existing["source_type"].to_s
        existing_type.empty? || existing_type == source_type.to_s
      end
      rows.concat(resolved)
      true
    end

    # ── Conditions shared helper ────────────────────────────────────

    def apply_conditions(sheet, add, remove)
      current = CoercedMutationArray.coerce(sheet.conditions, field: "sheet.conditions", log: @log).dup
      changed = false

      CoercedMutationArray.coerce(remove, field: "conditions_remove", log: @log).each do |cond|
        next unless CharacterStats::Conditions.valid?(cond)

        changed = true if current.delete(cond)
      end

      CoercedMutationArray.coerce(add, field: "conditions_add", log: @log).each do |cond|
        next unless CharacterStats::Conditions.valid?(cond)

        current = CharacterStats::Conditions.upgrade(current, cond)
        changed = true
      end

      sheet.update!(conditions: current.uniq) if changed
      changed
    end
  end
end
