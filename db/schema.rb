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

ActiveRecord::Schema[7.1].define(version: 2026_02_24_290001) do
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

  create_table "adventures", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.bigint "story_state_id", null: false
    t.text "character_effects"
    t.integer "character_gold", default: 0, null: false
    t.text "character_items"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "character_snapshot", default: {}, null: false
    t.bigint "user_id", null: false
    t.integer "character_hp", default: 0, null: false
    t.integer "character_max_hp", default: 0, null: false
    t.index ["sheet_id"], name: "index_adventures_on_sheet_id"
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
    t.index ["user_id"], name: "index_sheets_on_user_id"
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
  add_foreign_key "adventures", "sheets"
  add_foreign_key "adventures", "story_states"
  add_foreign_key "adventures", "users"
  add_foreign_key "ai_logs", "adventures"
  add_foreign_key "dm_logs", "adventures"
  add_foreign_key "dm_logs", "users"
  add_foreign_key "sheets", "users"
  add_foreign_key "story_states", "stories"
end
