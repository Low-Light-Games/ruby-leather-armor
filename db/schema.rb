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

ActiveRecord::Schema[7.1].define(version: 2026_03_09_150521) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "adventure_messages", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.string "message_type", default: "narrative", null: false
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id", "created_at"], name: "index_adventure_messages_on_adventure_id_and_created_at"
    t.index ["adventure_id"], name: "index_adventure_messages_on_adventure_id"
  end

  create_table "adventure_sheet_feats", force: :cascade do |t|
    t.bigint "adventure_sheet_id", null: false
    t.string "feat_id", null: false
    t.string "choice"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.jsonb "traversal_context", default: {}, null: false
    t.jsonb "combat_context", default: {}, null: false
    t.jsonb "social_context", default: {}, null: false
    t.jsonb "exploration_context", default: {}, null: false
    t.jsonb "rest_context", default: {}, null: false
    t.jsonb "inventory_context", default: {}, null: false
    t.text "scene_summary"
    t.bigint "current_location_id"
    t.jsonb "enriched_world", default: {}, null: false
    t.text "enriched_premise"
    t.jsonb "plot_state", default: {}, null: false
    t.jsonb "dm_settings", default: {}, null: false
    t.jsonb "time_context", default: {"current_hour"=>8, "adventure_day"=>1, "light_conditions"=>"day", "hours_since_last_rest"=>0, "hours_since_last_encounter_check"=>0}, null: false
    t.jsonb "scene_history", default: [], null: false
    t.index ["current_location_id"], name: "index_adventures_on_current_location_id"
    t.index ["story_id"], name: "index_adventures_on_story_id"
    t.index ["user_id"], name: "index_adventures_on_user_id"
  end

  create_table "ai_logs", force: :cascade do |t|
    t.bigint "adventure_id"
    t.string "call_type", null: false
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
    t.string "pipeline_run_id"
    t.text "player_message_content"
    t.integer "duration_ms"
    t.bigint "ai_usage_record_id"
    t.index ["adventure_id"], name: "index_ai_logs_on_adventure_id"
    t.index ["ai_usage_record_id"], name: "index_ai_logs_on_ai_usage_record_id"
    t.index ["created_at"], name: "index_ai_logs_on_created_at"
    t.index ["dm_service"], name: "index_ai_logs_on_dm_service"
    t.index ["pipeline_run_id"], name: "index_ai_logs_on_pipeline_run_id"
    t.index ["player_message_id"], name: "index_ai_logs_on_player_message_id"
    t.index ["status"], name: "index_ai_logs_on_status"
  end

  create_table "ai_usage_records", force: :cascade do |t|
    t.bigint "adventure_id"
    t.bigint "user_id"
    t.string "pipeline_run_id"
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
    t.string "call_type"
    t.index ["adventure_id"], name: "index_ai_usage_records_on_adventure_id"
    t.index ["ai_log_id"], name: "index_ai_usage_records_on_ai_log_id"
    t.index ["call_type"], name: "index_ai_usage_records_on_call_type"
    t.index ["created_at"], name: "index_ai_usage_records_on_created_at"
    t.index ["model_id", "created_at"], name: "index_ai_usage_records_on_model_id_and_created_at"
    t.index ["model_id"], name: "index_ai_usage_records_on_model_id"
    t.index ["pipeline_run_id"], name: "index_ai_usage_records_on_pipeline_run_id"
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
    t.index ["cr"], name: "index_bestiary_entries_on_cr"
    t.index ["creature_type"], name: "index_bestiary_entries_on_creature_type"
  end

  create_table "creature_sheet_feats", force: :cascade do |t|
    t.bigint "creature_sheet_id", null: false
    t.string "feat_id", null: false
    t.string "choice"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creature_sheet_id", "feat_id", "choice"], name: "idx_creature_sheet_feats_unique", unique: true
    t.index ["creature_sheet_id"], name: "index_creature_sheet_feats_on_creature_sheet_id"
  end

  create_table "creature_sheet_items", force: :cascade do |t|
    t.bigint "creature_sheet_id", null: false
    t.string "item_definition_id", null: false
    t.integer "quantity", default: 1, null: false
    t.boolean "equipped", default: false, null: false
    t.string "slot_override"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creature_sheet_id"], name: "index_creature_sheet_items_on_creature_sheet_id"
    t.index ["item_definition_id"], name: "index_creature_sheet_items_on_item_definition_id"
  end

  create_table "creature_sheet_spells", force: :cascade do |t|
    t.bigint "creature_sheet_id", null: false
    t.string "spell_id", null: false
    t.string "storage_type", default: "known", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creature_sheet_id", "spell_id", "storage_type"], name: "idx_creature_sheet_spells_unique", unique: true
    t.index ["creature_sheet_id"], name: "index_creature_sheet_spells_on_creature_sheet_id"
  end

  create_table "creature_sheets", force: :cascade do |t|
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
    t.index ["adventure_id", "name"], name: "index_creature_sheets_on_adventure_id_and_name"
    t.index ["adventure_id"], name: "index_creature_sheets_on_adventure_id"
  end

  create_table "dm_configs", force: :cascade do |t|
    t.json "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dm_logs", force: :cascade do |t|
    t.bigint "adventure_id"
    t.bigint "user_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id"], name: "index_dm_logs_on_adventure_id"
    t.index ["created_at"], name: "index_dm_logs_on_created_at"
    t.index ["user_id"], name: "index_dm_logs_on_user_id"
  end

  create_table "encounter_table_entries", force: :cascade do |t|
    t.bigint "encounter_table_id", null: false
    t.string "title", null: false
    t.text "description", null: false
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
    t.boolean "enabled", default: false, null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_feature_flags_on_key", unique: true
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

  create_table "location_connections", force: :cascade do |t|
    t.bigint "from_location_id", null: false
    t.bigint "to_location_id", null: false
    t.decimal "distance_miles", precision: 8, scale: 2, null: false
    t.string "terrain_type", default: "road", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["from_location_id", "to_location_id"], name: "idx_location_connections_pair", unique: true
    t.index ["from_location_id"], name: "index_location_connections_on_from_location_id"
    t.index ["to_location_id"], name: "index_location_connections_on_to_location_id"
  end

  create_table "pipeline_runs", force: :cascade do |t|
    t.string "pipeline_run_id", null: false
    t.bigint "adventure_id", null: false
    t.bigint "player_message_id"
    t.string "status", default: "running", null: false
    t.integer "active_duration_ms", default: 0, null: false
    t.integer "step_count", default: 0, null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id"], name: "index_pipeline_runs_on_adventure_id"
    t.index ["pipeline_run_id"], name: "index_pipeline_runs_on_pipeline_run_id", unique: true
    t.index ["started_at"], name: "index_pipeline_runs_on_started_at"
  end

  create_table "sheet_feats", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.string "feat_id", null: false
    t.string "choice"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["equipped_armor_id"], name: "index_sheets_on_equipped_armor_id"
    t.index ["equipped_shield_id"], name: "index_sheets_on_equipped_shield_id"
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
    t.text "initial_context"
    t.text "initial_summary"
    t.text "hook"
    t.jsonb "initial_contexts", default: {}, null: false
    t.index ["discarded_at"], name: "index_stories_on_discarded_at"
  end

  create_table "story_clues", force: :cascade do |t|
    t.bigint "story_id", null: false
    t.bigint "adventure_id"
    t.string "source", default: "manual", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "discovery_method", default: "exploration", null: false
    t.bigint "location_id"
    t.bigint "npc_id"
    t.integer "prerequisite_clue_ids", default: [], array: true
    t.text "reveals_secret"
    t.string "difficulty", default: "moderate", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id"], name: "index_story_clues_on_adventure_id"
    t.index ["location_id"], name: "index_story_clues_on_location_id"
    t.index ["npc_id"], name: "index_story_clues_on_npc_id"
    t.index ["story_id"], name: "index_story_clues_on_story_id"
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

  create_table "story_milestones", force: :cascade do |t|
    t.bigint "story_id", null: false
    t.string "source", default: "manual", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.integer "trigger_clue_ids", default: [], array: true
    t.text "consequence"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["story_id"], name: "index_story_milestones_on_story_id"
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
    t.index ["adventure_id"], name: "index_story_npcs_on_adventure_id"
    t.index ["location_id"], name: "index_story_npcs_on_location_id"
    t.index ["story_id"], name: "index_story_npcs_on_story_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.boolean "admin"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "adventure_messages", "adventures"
  add_foreign_key "adventure_sheet_feats", "adventure_sheets"
  add_foreign_key "adventure_sheet_feats", "feat_definitions", column: "feat_id"
  add_foreign_key "adventure_sheet_items", "adventure_sheets"
  add_foreign_key "adventure_sheet_items", "item_definitions"
  add_foreign_key "adventure_sheet_spells", "adventure_sheets"
  add_foreign_key "adventure_sheet_spells", "spell_definitions", column: "spell_id"
  add_foreign_key "adventure_sheets", "adventures"
  add_foreign_key "adventure_sheets", "sheets"
  add_foreign_key "adventures", "stories"
  add_foreign_key "adventures", "story_locations", column: "current_location_id"
  add_foreign_key "adventures", "users"
  add_foreign_key "ai_logs", "adventure_messages", column: "player_message_id", on_delete: :nullify
  add_foreign_key "ai_logs", "adventures", on_delete: :nullify
  add_foreign_key "ai_logs", "ai_usage_records", on_delete: :nullify
  add_foreign_key "creature_sheet_feats", "creature_sheets"
  add_foreign_key "creature_sheet_feats", "feat_definitions", column: "feat_id"
  add_foreign_key "creature_sheet_items", "creature_sheets"
  add_foreign_key "creature_sheet_items", "item_definitions"
  add_foreign_key "creature_sheet_spells", "creature_sheets"
  add_foreign_key "creature_sheet_spells", "spell_definitions", column: "spell_id"
  add_foreign_key "creature_sheets", "adventures"
  add_foreign_key "dm_logs", "adventures", on_delete: :nullify
  add_foreign_key "dm_logs", "users"
  add_foreign_key "encounter_table_entries", "encounter_tables"
  add_foreign_key "encounter_tables", "stories"
  add_foreign_key "location_connections", "story_locations", column: "from_location_id"
  add_foreign_key "location_connections", "story_locations", column: "to_location_id"
  add_foreign_key "sheet_feats", "feat_definitions", column: "feat_id"
  add_foreign_key "sheet_feats", "sheets"
  add_foreign_key "sheet_items", "item_definitions"
  add_foreign_key "sheet_items", "sheets"
  add_foreign_key "sheet_spells", "sheets"
  add_foreign_key "sheet_spells", "spell_definitions", column: "spell_id"
  add_foreign_key "sheets", "users"
  add_foreign_key "story_clues", "adventures"
  add_foreign_key "story_clues", "stories"
  add_foreign_key "story_clues", "story_locations", column: "location_id", on_delete: :nullify
  add_foreign_key "story_clues", "story_npcs", column: "npc_id"
  add_foreign_key "story_locations", "stories"
  add_foreign_key "story_milestones", "stories"
  add_foreign_key "story_npcs", "adventures"
  add_foreign_key "story_npcs", "stories"
  add_foreign_key "story_npcs", "story_locations", column: "location_id", on_delete: :nullify
end
