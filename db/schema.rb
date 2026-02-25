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

ActiveRecord::Schema[7.1].define(version: 2026_02_25_300009) do
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
    t.integer "gold", default: 0, null: false
    t.integer "hp", default: 0, null: false
    t.integer "max_hp", default: 0, null: false
    t.text "items"
    t.text "effects"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "derived_stats", default: {}, null: false
    t.index ["adventure_id"], name: "index_adventure_sheets_on_adventure_id"
    t.index ["sheet_id"], name: "index_adventure_sheets_on_sheet_id"
  end

  create_table "adventures", force: :cascade do |t|
    t.bigint "story_state_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["story_state_id"], name: "index_adventures_on_story_state_id"
    t.index ["user_id"], name: "index_adventures_on_user_id"
  end

  create_table "ai_logs", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.string "call_type", null: false
    t.text "prompt_summary", null: false
    t.text "raw_response"
    t.text "parsed_response"
    t.string "status", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id"], name: "index_ai_logs_on_adventure_id"
    t.index ["created_at"], name: "index_ai_logs_on_created_at"
    t.index ["status"], name: "index_ai_logs_on_status"
  end

  create_table "dm_configs", force: :cascade do |t|
    t.json "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dm_logs", force: :cascade do |t|
    t.bigint "adventure_id", null: false
    t.bigint "user_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adventure_id"], name: "index_dm_logs_on_adventure_id"
    t.index ["created_at"], name: "index_dm_logs_on_created_at"
    t.index ["user_id"], name: "index_dm_logs_on_user_id"
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

  create_table "sheet_feats", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.string "feat_id", null: false
    t.string "choice"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sheet_id", "feat_id", "choice"], name: "idx_sheet_feats_unique", unique: true
    t.index ["sheet_id"], name: "index_sheet_feats_on_sheet_id"
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
    t.index ["discarded_at"], name: "index_stories_on_discarded_at"
  end

  create_table "story_states", force: :cascade do |t|
    t.bigint "story_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description", default: "", null: false
    t.integer "position", default: 0, null: false
    t.datetime "discarded_at"
    t.index ["discarded_at"], name: "index_story_states_on_discarded_at"
    t.index ["story_id"], name: "index_story_states_on_story_id"
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
  add_foreign_key "adventure_sheet_spells", "adventure_sheets"
  add_foreign_key "adventure_sheet_spells", "spell_definitions", column: "spell_id"
  add_foreign_key "adventure_sheets", "adventures"
  add_foreign_key "adventure_sheets", "sheets"
  add_foreign_key "adventures", "story_states"
  add_foreign_key "adventures", "users"
  add_foreign_key "ai_logs", "adventures"
  add_foreign_key "dm_logs", "adventures"
  add_foreign_key "dm_logs", "users"
  add_foreign_key "sheet_feats", "feat_definitions", column: "feat_id"
  add_foreign_key "sheet_feats", "sheets"
  add_foreign_key "sheet_spells", "sheets"
  add_foreign_key "sheet_spells", "spell_definitions", column: "spell_id"
  add_foreign_key "sheets", "users"
  add_foreign_key "story_states", "stories"
end
