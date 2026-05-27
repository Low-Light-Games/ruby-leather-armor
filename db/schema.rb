# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_05_27_010000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "vector"

  create_table "adventure_actor_sheet_feats", force: :cascade do |t|
    t.bigint "actor_sheet_id", null: false
    t.string "feat_id", null: false
    t.string "choice"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_sheet_id", "feat_id", "choice"], name: "idx_adventure_actor_sheet_feats_unique", unique: true
    t.index ["actor_sheet_id"], name: "index_adventure_actor_sheet_feats_on_actor_sheet_id"
  end

  create_table "adventure_actor_sheet_items", force: :cascade do |t|
    t.bigint "actor_sheet_id", null: false
    t.string "item_definition_id", null: false
    t.integer "quantity", default: 1, null: false
    t.boolean "equipped", default: false, null: false
    t.string "slot_override"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_sheet_id"], name: "index_adventure_actor_sheet_items_on_actor_sheet_id"
    t.index ["item_definition_id"], name: "index_adventure_actor_sheet_items_on_item_definition_id"
  end

  create_table "adventure_actor_sheet_spells", force: :cascade do |t|
    t.bigint "actor_sheet_id", null: false
    t.string "spell_id", null: false
    t.string "storage_type", default: "known", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_sheet_id", "spell_id", "storage_type"], name: "idx_adventure_actor_sheet_spells_unique", unique: true
    t.index ["actor_sheet_id"], name: "index_adventure_actor_sheet_spells_on_actor_sheet_id"
  end

  create_table "adventure_actor_sheets", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "creature_type", default: "npc", null: false
    t.string "attitude", default: "indifferent"
    t.integer "strength", default: 10, null: false
    t.integer "dexterity", default: 10, null: false
    t.integer "constitution", default: 10, null: false
    t.integer "intelligence", default: 10, null: false
    t.integer "wisdom", default: 10, null: false
    t.integer "charisma", default: 10, null: false
    t.integer "level", default: 1, null: false
    t.string "race"
    t.string "racial_bonus_attribute"
    t.string "character_class"
    t.integer "hp", default: 0, null: false
    t.integer "max_hp", default: 0, null: false
    t.jsonb "derived_stats", default: {}, null: false
    t.string "equipped_armor_id"
    t.string "equipped_shield_id"
    t.jsonb "equipped_weapons", default: [], null: false
    t.jsonb "details", default: {}, null: false
    t.jsonb "currency", default: {"gold"=>0, "copper"=>0, "silver"=>0, "platinum"=>0}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "origin", default: "unknown"
    t.jsonb "conditions", default: [], null: false
    t.jsonb "behavior_policy", default: {}, null: false
    t.index ["adventure_id", "name"], name: "index_adventure_actor_sheets_on_adventure_id_and_name"
    t.index ["adventure_id"], name: "index_adventure_actor_sheets_on_adventure_id"
  end

  create_table "adventure_battlefields", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.string "status", default: "active", null: false
    t.string "topology", default: "square", null: false
    t.jsonb "world", default: {}, null: false
    t.jsonb "tokens", default: {}, null: false
    t.jsonb "viewport", default: {}, null: false
    t.integer "version", default: 1, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id", "status"], name: "index_adventure_battlefields_on_adventure_id_and_status"
    t.index ["adventure_id"], name: "index_adventure_battlefields_on_adventure_id"
  end

  create_table "adventure_locations", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.bigint "story_location_id"
    t.string "name", null: false
    t.text "description"
    t.float "x", default: 0.0, null: false
    t.float "y", default: 0.0, null: false
    t.string "source", null: false
    t.vector "embedding", limit: 1536
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id", "name"], name: "index_adventure_locations_seed_unique_per_adventure", unique: true, where: "((source)::text = 'seed'::text)"
    t.index ["adventure_id"], name: "index_adventure_locations_on_adventure_id"
    t.index ["embedding"], name: "index_adventure_locations_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["story_location_id"], name: "index_adventure_locations_on_story_location_id"
  end

  create_table "adventure_loops", force: :cascade do |t|
    t.bigint "adventure_id"
    t.string "registry_entry_uuid", null: false
    t.integer "sequence_index", default: 0, null: false
    t.text "raw_action"
    t.text "player_intent"
    t.string "category"
    t.string "status", default: "pending", null: false
    t.jsonb "tags", default: {}, null: false
    t.jsonb "data", default: {}, null: false
    t.jsonb "timeline", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "pipeline_id"
    t.index ["adventure_id", "created_at"], name: "index_adventure_loops_on_adventure_id_and_created_at"
    t.index ["adventure_id"], name: "index_adventure_loops_on_adventure_id"
    t.index ["pipeline_id"], name: "index_adventure_loops_on_pipeline_id"
    t.index ["registry_entry_uuid", "sequence_index"], name: "idx_on_registry_entry_uuid_sequence_index_658caad47b"
    t.index ["registry_entry_uuid", "status"], name: "index_adventure_loops_on_registry_entry_uuid_and_status"
    t.index ["registry_entry_uuid"], name: "index_adventure_loops_on_registry_entry_uuid"
  end

  create_table "adventure_messages", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.string "message_type", default: "narrative", null: false
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["adventure_id", "created_at"], name: "index_adventure_messages_on_adventure_id_and_created_at"
    t.index ["adventure_id"], name: "index_adventure_messages_on_adventure_id"
    t.index ["user_id", "created_at"], name: "index_adventure_messages_on_user_id_and_created_at"
  end

  create_table "adventure_narrative_facts", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.text "text", null: false
    t.string "kind", null: false
    t.text "entities", default: [], array: true
    t.string "polarity", default: "asserts", null: false
    t.vector "embedding", limit: 1536
    t.bigint "introduced_at_loop_id"
    t.bigint "invalidated_at_loop_id"
    t.bigint "invalidated_by_fact_id"
    t.string "source", null: false
    t.integer "source_idx"
    t.datetime "created_at", null: false
    t.index ["adventure_id", "introduced_at_loop_id", "source_idx"], name: "index_narrative_facts_loremaster_source_idx_uniq", unique: true, where: "((source)::text = 'loremaster'::text)"
    t.index ["adventure_id"], name: "index_adventure_narrative_facts_on_adventure_id"
    t.index ["adventure_id"], name: "index_narrative_facts_active_by_adventure", where: "(invalidated_at_loop_id IS NULL)"
    t.index ["embedding"], name: "index_narrative_facts_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["introduced_at_loop_id"], name: "index_adventure_narrative_facts_on_introduced_at_loop_id"
    t.index ["invalidated_at_loop_id"], name: "index_adventure_narrative_facts_on_invalidated_at_loop_id"
    t.index ["invalidated_by_fact_id"], name: "index_adventure_narrative_facts_on_invalidated_by_fact_id"
  end

  create_table "adventure_npcs", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.bigint "story_npc_id"
    t.string "name", null: false
    t.text "description"
    t.string "attitude", default: "indifferent", null: false
    t.string "location_name"
    t.string "source", null: false
    t.vector "embedding", limit: 1536
    t.bigint "last_seen_loop_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "actor_sheet_id"
    t.index ["actor_sheet_id"], name: "index_adventure_npcs_on_actor_sheet_id"
    t.index ["adventure_id", "location_name"], name: "index_adventure_npcs_on_adventure_and_location"
    t.index ["adventure_id", "name"], name: "index_adventure_npcs_seed_unique_per_adventure", unique: true, where: "((source)::text = 'seed'::text)"
    t.index ["adventure_id"], name: "index_adventure_npcs_on_adventure_id"
    t.index ["embedding"], name: "index_adventure_npcs_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["last_seen_loop_id"], name: "index_adventure_npcs_on_last_seen_loop_id"
    t.index ["story_npc_id"], name: "index_adventure_npcs_on_story_npc_id"
  end

  create_table "adventure_sheet_feats", force: :cascade do |t|
    t.bigint "adventure_sheet_id", null: false
    t.string "feat_id", null: false
    t.string "choice"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "pool", default: "general", null: false
    t.index ["adventure_sheet_id", "feat_id", "choice"], name: "idx_adv_sheet_feats_unique", unique: true
    t.index ["adventure_sheet_id"], name: "index_adventure_sheet_feats_on_adventure_sheet_id"
  end

  create_table "adventure_sheet_items", force: :cascade do |t|
    t.bigint "adventure_sheet_id", null: false
    t.string "item_definition_id", null: false
    t.integer "quantity", default: 1, null: false
    t.boolean "equipped", default: false, null: false
    t.string "slot_override"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_sheet_id"], name: "index_adventure_sheet_items_on_adventure_sheet_id"
    t.index ["item_definition_id"], name: "index_adventure_sheet_items_on_item_definition_id"
  end

  create_table "adventure_sheet_spells", force: :cascade do |t|
    t.bigint "adventure_sheet_id", null: false
    t.string "spell_id", null: false
    t.string "storage_type", default: "known", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_sheet_id", "spell_id", "storage_type"], name: "idx_adv_sheet_spells_unique", unique: true
    t.index ["adventure_sheet_id"], name: "index_adventure_sheet_spells_on_adventure_sheet_id"
  end

  create_table "adventure_sheets", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.bigint "sheet_id"
    t.string "name", null: false
    t.text "description"
    t.integer "strength", null: false
    t.integer "intelligence", null: false
    t.integer "dexterity", null: false
    t.integer "constitution", null: false
    t.integer "wisdom", null: false
    t.integer "charisma", null: false
    t.string "race"
    t.string "racial_bonus_attribute"
    t.string "character_class"
    t.string "subclass"
    t.integer "level", default: 1, null: false
    t.json "details"
    t.integer "hp", default: 0, null: false
    t.integer "max_hp", default: 0, null: false
    t.text "items"
    t.text "effects"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "derived_stats", default: {}, null: false
    t.string "equipped_armor_id"
    t.string "equipped_shield_id"
    t.jsonb "equipped_weapons", default: [], null: false
    t.jsonb "currency", default: {"gold"=>0, "copper"=>0, "silver"=>0, "platinum"=>0}, null: false
    t.jsonb "conditions", default: [], null: false
    t.jsonb "skill_ranks", default: {}, null: false
    t.jsonb "active_buffs", default: [], null: false
    t.index ["adventure_id"], name: "index_adventure_sheets_on_adventure_id"
    t.index ["equipped_armor_id"], name: "index_adventure_sheets_on_equipped_armor_id"
    t.index ["equipped_shield_id"], name: "index_adventure_sheets_on_equipped_shield_id"
    t.index ["sheet_id"], name: "index_adventure_sheets_on_sheet_id"
  end

  create_table "adventures", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "story_id", null: false
    t.text "story_summary"
    t.string "current_category"
    t.string "dm_mode", default: "standard", null: false
    t.boolean "directed_dm", default: false, null: false
    t.jsonb "combat_context", default: {}, null: false
    t.bigint "current_location_id"
    t.jsonb "dm_settings", default: {}, null: false
    t.jsonb "time_context", default: {"current_hour"=>8, "adventure_day"=>1, "light_conditions"=>"day", "hours_since_last_rest"=>0, "hours_since_last_encounter_check"=>0}, null: false
    t.datetime "discarded_at"
    t.boolean "skip_world_sanity_check", default: false, null: false
    t.datetime "ended_at"
    t.string "end_reason"
    t.float "coordinate_scale", default: 7.0, null: false
    t.boolean "use_gamemaster_orchestrator", default: false, null: false
    t.index ["current_location_id"], name: "index_adventures_on_current_location_id"
    t.index ["discarded_at"], name: "index_adventures_on_discarded_at"
    t.index ["ended_at"], name: "index_adventures_on_ended_at"
    t.index ["story_id"], name: "index_adventures_on_story_id"
    t.index ["user_id"], name: "index_adventures_on_user_id"
  end

  create_table "ai_usage_records", force: :cascade do |t|
    t.bigint "adventure_id"
    t.bigint "user_id"
    t.string "registry_entry_uuid"
    t.bigint "ai_log_id"
    t.string "model_id", null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.integer "reasoning_tokens", default: 0, null: false
    t.integer "total_tokens", default: 0, null: false
    t.bigint "input_cost_microdollars", default: 0, null: false
    t.bigint "output_cost_microdollars", default: 0, null: false
    t.bigint "total_cost_microdollars", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "event_type"
    t.bigint "adventure_loop_id"
    t.integer "loop_sequence_index"
    t.index ["adventure_id"], name: "index_ai_usage_records_on_adventure_id"
    t.index ["adventure_loop_id"], name: "index_ai_usage_records_on_adventure_loop_id"
    t.index ["ai_log_id"], name: "index_ai_usage_records_on_ai_log_id"
    t.index ["created_at"], name: "index_ai_usage_records_on_created_at"
    t.index ["event_type"], name: "index_ai_usage_records_on_event_type"
    t.index ["model_id", "created_at"], name: "index_ai_usage_records_on_model_id_and_created_at"
    t.index ["model_id"], name: "index_ai_usage_records_on_model_id"
    t.index ["registry_entry_uuid"], name: "index_ai_usage_records_on_registry_entry_uuid"
    t.index ["user_id"], name: "index_ai_usage_records_on_user_id"
  end

  create_table "bestiary_entries", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.string "source", default: "Pathfinder Roleplaying Game Reference Document (OGL)", null: false
    t.decimal "cr", precision: 5, scale: 1
    t.string "creature_type"
    t.string "alignment"
    t.string "size", default: "Medium"
    t.integer "strength", default: 10
    t.integer "dexterity", default: 10
    t.integer "constitution", default: 10
    t.integer "intelligence", default: 10
    t.integer "wisdom", default: 10
    t.integer "charisma", default: 10
    t.string "hp_formula"
    t.integer "ac", default: 10
    t.integer "base_attack", default: 0
    t.integer "speed", default: 30
    t.jsonb "special_abilities", default: []
    t.jsonb "feats", default: []
    t.jsonb "skills", default: {}
    t.text "description"
    t.string "environment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "story_id"
    t.string "default_for_type"
    t.index ["cr"], name: "index_bestiary_entries_on_cr"
    t.index ["creature_type"], name: "index_bestiary_entries_on_creature_type"
    t.index ["default_for_type"], name: "index_bestiary_entries_on_default_for_type_unique", unique: true, where: "(default_for_type IS NOT NULL)"
    t.index ["story_id"], name: "index_bestiary_entries_on_story_id"
  end

  create_table "class_ability_definitions", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.string "pf1e_class", null: false
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "effects", default: [], null: false
    t.jsonb "duration_formula"
    t.index ["name"], name: "index_class_ability_definitions_on_name"
    t.index ["pf1e_class"], name: "index_class_ability_definitions_on_pf1e_class"
  end

  create_table "dm_configs", force: :cascade do |t|
    t.json "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "encounter_table_entries", force: :cascade do |t|
    t.bigint "encounter_table_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "entry_type", default: "fixed", null: false
    t.integer "weight", default: 1, null: false
    t.string "terrain_types"
    t.integer "min_party_level"
    t.integer "max_party_level"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "creature_manifest", default: [], null: false
    t.index ["encounter_table_id"], name: "index_encounter_table_entries_on_encounter_table_id"
  end

  create_table "encounter_tables", force: :cascade do |t|
    t.bigint "story_id"
    t.string "name", null: false
    t.text "description"
    t.integer "check_frequency_hours", default: 4, null: false
    t.integer "encounter_chance", default: 15, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["story_id"], name: "index_encounter_tables_on_story_id"
  end

  create_table "experience_suggestions", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.uuid "registry_entry_uuid"
    t.string "category", null: false
    t.string "source_step", null: false
    t.jsonb "details", default: {}, null: false
    t.boolean "reviewed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id"], name: "index_experience_suggestions_on_adventure_id"
    t.index ["category"], name: "index_experience_suggestions_on_category"
    t.index ["reviewed"], name: "index_experience_suggestions_on_reviewed"
  end

  create_table "feat_definitions", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.string "category", null: false
    t.text "summary"
    t.boolean "repeatable", default: false, null: false
    t.string "choice_type"
    t.jsonb "prerequisites", default: [], null: false
    t.jsonb "effects", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_feat_definitions_on_category"
    t.index ["name"], name: "index_feat_definitions_on_name"
  end

  create_table "feature_flags", force: :cascade do |t|
    t.string "key", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mode", default: "off", null: false
    t.string "bucketing_strategy"
    t.integer "granular_user_ids", default: [], null: false, array: true
    t.integer "modulo_divisor"
    t.integer "modulo_on_remainders", default: [], null: false, array: true
    t.index ["key"], name: "index_feature_flags_on_key", unique: true
  end

  create_table "feedbacks", force: :cascade do |t|
    t.bigint "user_id"
    t.text "body", null: false
    t.string "page_url"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_feedbacks_on_user_id"
  end

  create_table "item_definitions", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.string "item_type", null: false
    t.string "category"
    t.decimal "cost_gp", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "weight", precision: 8, scale: 2, default: "0.0", null: false
    t.integer "armor_bonus", default: 0
    t.integer "max_dex_bonus"
    t.integer "armor_check_penalty", default: 0
    t.integer "speed_30"
    t.integer "speed_20"
    t.jsonb "properties", default: {}, null: false
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slot", default: "none", null: false
    t.integer "shield_bonus", default: 0, null: false
    t.integer "arcane_spell_failure", default: 0, null: false
    t.string "weapon_category"
    t.string "weapon_type"
    t.string "damage_dice"
    t.string "critical_range"
    t.string "damage_type"
    t.integer "range_increment"
    t.jsonb "effects", default: [], null: false
    t.index ["category"], name: "index_item_definitions_on_category"
    t.index ["item_type"], name: "index_item_definitions_on_item_type"
    t.index ["name"], name: "index_item_definitions_on_name"
    t.index ["slot"], name: "index_item_definitions_on_slot"
  end

  create_table "moderation_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "input_excerpt"
    t.jsonb "flagged_categories", default: {}, null: false
    t.integer "strike_number", null: false
    t.boolean "auto_banned", default: false, null: false
    t.boolean "auto_untrusted", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_moderation_events_on_created_at"
    t.index ["user_id"], name: "index_moderation_events_on_user_id"
  end

  create_table "pipeline_registry_entries", force: :cascade do |t|
    t.string "registry_entry_uuid", null: false
    t.bigint "adventure_id", null: false
    t.bigint "player_message_id"
    t.string "status", default: "running", null: false
    t.integer "active_duration_ms", default: 0, null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "app_version"
    t.index ["adventure_id"], name: "index_pipeline_registry_entries_on_adventure_id"
    t.index ["registry_entry_uuid"], name: "index_pipeline_registry_entries_on_registry_entry_uuid", unique: true
    t.index ["started_at"], name: "index_pipeline_registry_entries_on_started_at"
  end

  create_table "pipelines", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.bigint "player_message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id"], name: "index_pipelines_on_adventure_id"
    t.index ["player_message_id"], name: "index_pipelines_on_player_message_id"
  end

  create_table "play_logs", force: :cascade do |t|
    t.bigint "adventure_id"
    t.string "event_type", null: false
    t.text "prompt_summary", null: false
    t.text "raw_response"
    t.text "parsed_response"
    t.string "status", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "request_body"
    t.string "dm_service", default: "standard", null: false
    t.string "model_used"
    t.bigint "player_message_id"
    t.string "registry_entry_uuid"
    t.text "player_message_content"
    t.integer "duration_ms"
    t.bigint "ai_usage_record_id"
    t.string "app_version"
    t.bigint "adventure_loop_id"
    t.integer "loop_sequence_index"
    t.string "reasoning_effort"
    t.index ["adventure_id"], name: "index_play_logs_on_adventure_id"
    t.index ["adventure_loop_id"], name: "index_play_logs_on_adventure_loop_id"
    t.index ["ai_usage_record_id"], name: "index_play_logs_on_ai_usage_record_id"
    t.index ["created_at"], name: "index_play_logs_on_created_at"
    t.index ["dm_service"], name: "index_play_logs_on_dm_service"
    t.index ["player_message_id"], name: "index_play_logs_on_player_message_id"
    t.index ["registry_entry_uuid"], name: "index_play_logs_on_registry_entry_uuid"
    t.index ["status"], name: "index_play_logs_on_status"
  end

  create_table "rule_embeddings", force: :cascade do |t|
    t.string "slug", null: false
    t.string "domain", null: false
    t.string "name", null: false
    t.text "brief"
    t.text "body", null: false
    t.string "text_digest", null: false
    t.vector "embedding", limit: 1536
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_rule_embeddings_on_domain"
    t.index ["embedding"], name: "index_rule_embeddings_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["slug"], name: "index_rule_embeddings_on_slug", unique: true
  end

  create_table "sheet_feats", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.string "feat_id", null: false
    t.string "choice"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "pool", default: "general", null: false
    t.index ["sheet_id", "feat_id", "choice"], name: "idx_sheet_feats_unique", unique: true
    t.index ["sheet_id"], name: "index_sheet_feats_on_sheet_id"
  end

  create_table "sheet_items", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.string "item_definition_id", null: false
    t.integer "quantity", default: 1, null: false
    t.boolean "equipped", default: false, null: false
    t.string "slot_override"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_definition_id"], name: "index_sheet_items_on_item_definition_id"
    t.index ["sheet_id"], name: "index_sheet_items_on_sheet_id"
  end

  create_table "sheet_spells", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.string "spell_id", null: false
    t.string "storage_type", default: "known", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sheet_id", "spell_id", "storage_type"], name: "idx_sheet_spells_unique", unique: true
    t.index ["sheet_id"], name: "index_sheet_spells_on_sheet_id"
  end

  create_table "sheets", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.json "details"
    t.integer "strength"
    t.integer "intelligence"
    t.integer "dexterity"
    t.integer "constitution"
    t.integer "wisdom"
    t.integer "charisma"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "race"
    t.string "racial_bonus_attribute"
    t.string "character_class"
    t.string "subclass"
    t.integer "level", default: 1, null: false
    t.jsonb "derived_stats", default: {}, null: false
    t.string "equipped_armor_id"
    t.string "equipped_shield_id"
    t.jsonb "equipped_weapons", default: [], null: false
    t.jsonb "currency", default: {"gold"=>0, "copper"=>0, "silver"=>0, "platinum"=>0}, null: false
    t.jsonb "skill_ranks", default: {}, null: false
    t.string "source_kind", default: "custom", null: false
    t.string "starter_key"
    t.index ["equipped_armor_id"], name: "index_sheets_on_equipped_armor_id"
    t.index ["equipped_shield_id"], name: "index_sheets_on_equipped_shield_id"
    t.index ["source_kind"], name: "index_sheets_on_source_kind"
    t.index ["user_id", "starter_key"], name: "index_sheets_on_user_id_and_starter_key", unique: true, where: "(starter_key IS NOT NULL)"
    t.index ["user_id"], name: "index_sheets_on_user_id"
  end

  create_table "spell_definitions", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.string "school", null: false
    t.string "subschool"
    t.jsonb "descriptors", default: [], null: false
    t.jsonb "class_levels", default: {}, null: false
    t.jsonb "components", default: [], null: false
    t.string "material_component"
    t.string "casting_time"
    t.string "range"
    t.string "duration"
    t.string "saving_throw"
    t.boolean "spell_resistance", default: false, null: false
    t.jsonb "effects", default: [], null: false
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "duration_formula"
    t.index ["class_levels"], name: "index_spell_definitions_on_class_levels", using: :gin
    t.index ["name"], name: "index_spell_definitions_on_name"
    t.index ["school"], name: "index_spell_definitions_on_school"
  end

  create_table "stories", force: :cascade do |t|
    t.string "title", null: false
    t.text "premise", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "preview", default: "", null: false
    t.datetime "discarded_at"
    t.string "world_terrain", default: "plains", null: false
    t.jsonb "seed_facts", default: [], null: false
    t.text "opening_message", default: "", null: false
    t.boolean "hidden_from_players", default: false, null: false
    t.index ["discarded_at"], name: "index_stories_on_discarded_at"
  end

  create_table "story_locations", force: :cascade do |t|
    t.bigint "story_id", null: false
    t.string "name", null: false
    t.text "description"
    t.boolean "starting", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["story_id", "name"], name: "index_story_locations_on_story_id_and_name", unique: true
    t.index ["story_id"], name: "index_story_locations_on_story_id"
  end

  create_table "story_npcs", force: :cascade do |t|
    t.bigint "story_id", null: false
    t.bigint "adventure_id"
    t.string "source", default: "manual", null: false
    t.string "name", null: false
    t.string "role", default: "bystander", null: false
    t.bigint "location_id"
    t.text "description"
    t.text "knowledge"
    t.string "attitude", default: "indifferent", null: false
    t.boolean "secret", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "bestiary_entry_id"
    t.index ["adventure_id"], name: "index_story_npcs_on_adventure_id"
    t.index ["bestiary_entry_id"], name: "index_story_npcs_on_bestiary_entry_id"
    t.index ["location_id"], name: "index_story_npcs_on_location_id"
    t.index ["story_id"], name: "index_story_npcs_on_story_id"
  end

  create_table "stripe_webhook_events", force: :cascade do |t|
    t.string "stripe_event_id", null: false
    t.string "event_type", null: false
    t.datetime "processed_at", null: false
    t.text "payload_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_event_id"], name: "index_stripe_webhook_events_on_stripe_event_id", unique: true
  end

  create_table "user_stripe_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "plan_key", default: "free", null: false
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.string "stripe_subscription_status"
    t.string "stripe_price_id"
    t.datetime "stripe_current_period_end"
    t.datetime "delinquent_since"
    t.datetime "grace_period_ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_customer_id"], name: "index_user_stripe_profiles_on_stripe_customer_id", unique: true
    t.index ["stripe_price_id"], name: "index_user_stripe_profiles_on_stripe_price_id"
    t.index ["stripe_subscription_id"], name: "index_user_stripe_profiles_on_stripe_subscription_id", unique: true
    t.index ["user_id"], name: "index_user_stripe_profiles_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.boolean "admin"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider"
    t.string "uid"
    t.string "onboarding_state", default: "new", null: false
    t.integer "moderation_strikes", default: 0, null: false
    t.boolean "banned", default: false, null: false
    t.datetime "banned_at"
    t.boolean "trusted", default: false, null: false
    t.string "combat_dice_strategy", default: "client", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["onboarding_state"], name: "index_users_on_onboarding_state"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
  end

  add_foreign_key "adventure_actor_sheet_feats", "adventure_actor_sheets", column: "actor_sheet_id"
  add_foreign_key "adventure_actor_sheet_feats", "feat_definitions", column: "feat_id"
  add_foreign_key "adventure_actor_sheet_items", "adventure_actor_sheets", column: "actor_sheet_id"
  add_foreign_key "adventure_actor_sheet_items", "item_definitions"
  add_foreign_key "adventure_actor_sheet_spells", "adventure_actor_sheets", column: "actor_sheet_id"
  add_foreign_key "adventure_actor_sheet_spells", "spell_definitions", column: "spell_id"
  add_foreign_key "adventure_actor_sheets", "adventures"
  add_foreign_key "adventure_battlefields", "adventures"
  add_foreign_key "adventure_locations", "adventures"
  add_foreign_key "adventure_locations", "story_locations"
  add_foreign_key "adventure_loops", "adventures", on_delete: :nullify
  add_foreign_key "adventure_loops", "pipelines"
  add_foreign_key "adventure_messages", "adventures"
  add_foreign_key "adventure_messages", "users"
  add_foreign_key "adventure_narrative_facts", "adventure_loops", column: "introduced_at_loop_id"
  add_foreign_key "adventure_narrative_facts", "adventure_loops", column: "invalidated_at_loop_id"
  add_foreign_key "adventure_narrative_facts", "adventure_narrative_facts", column: "invalidated_by_fact_id"
  add_foreign_key "adventure_narrative_facts", "adventures"
  add_foreign_key "adventure_npcs", "adventure_actor_sheets", column: "actor_sheet_id"
  add_foreign_key "adventure_npcs", "adventure_loops", column: "last_seen_loop_id"
  add_foreign_key "adventure_npcs", "adventures"
  add_foreign_key "adventure_npcs", "story_npcs"
  add_foreign_key "adventure_sheet_feats", "adventure_sheets"
  add_foreign_key "adventure_sheet_feats", "feat_definitions", column: "feat_id"
  add_foreign_key "adventure_sheet_items", "adventure_sheets"
  add_foreign_key "adventure_sheet_items", "item_definitions"
  add_foreign_key "adventure_sheet_spells", "adventure_sheets"
  add_foreign_key "adventure_sheet_spells", "spell_definitions", column: "spell_id"
  add_foreign_key "adventure_sheets", "adventures"
  add_foreign_key "adventure_sheets", "sheets"
  add_foreign_key "adventures", "adventure_locations", column: "current_location_id", on_delete: :nullify
  add_foreign_key "adventures", "stories"
  add_foreign_key "adventures", "users"
  add_foreign_key "bestiary_entries", "stories"
  add_foreign_key "encounter_table_entries", "encounter_tables"
  add_foreign_key "encounter_tables", "stories"
  add_foreign_key "experience_suggestions", "adventures"
  add_foreign_key "feedbacks", "users"
  add_foreign_key "moderation_events", "users"
  add_foreign_key "pipelines", "adventure_messages", column: "player_message_id", on_delete: :nullify
  add_foreign_key "pipelines", "adventures"
  add_foreign_key "play_logs", "adventure_messages", column: "player_message_id", on_delete: :nullify
  add_foreign_key "play_logs", "adventures", on_delete: :nullify
  add_foreign_key "play_logs", "ai_usage_records", on_delete: :nullify
  add_foreign_key "sheet_feats", "feat_definitions", column: "feat_id"
  add_foreign_key "sheet_feats", "sheets"
  add_foreign_key "sheet_items", "item_definitions"
  add_foreign_key "sheet_items", "sheets"
  add_foreign_key "sheet_spells", "sheets"
  add_foreign_key "sheet_spells", "spell_definitions", column: "spell_id"
  add_foreign_key "sheets", "users"
  add_foreign_key "story_locations", "stories"
  add_foreign_key "story_npcs", "adventures"
  add_foreign_key "story_npcs", "bestiary_entries"
  add_foreign_key "story_npcs", "stories"
  add_foreign_key "story_npcs", "story_locations", column: "location_id", on_delete: :nullify
  add_foreign_key "user_stripe_profiles", "users"
end
