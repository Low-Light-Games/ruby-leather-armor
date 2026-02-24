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

ActiveRecord::Schema[7.1].define(version: 2026_02_24_180001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "adventures", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.bigint "story_state_id", null: false
    t.text "character_effects"
    t.integer "character_gold", default: 0, null: false
    t.text "character_items"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sheet_id"], name: "index_adventures_on_sheet_id"
    t.index ["story_state_id"], name: "index_adventures_on_story_state_id"
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
    t.index ["user_id"], name: "index_sheets_on_user_id"
  end

  create_table "stories", force: :cascade do |t|
    t.string "title", null: false
    t.text "premise", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "preview", default: "", null: false
  end

  create_table "story_states", force: :cascade do |t|
    t.bigint "story_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description", default: "", null: false
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

  add_foreign_key "adventures", "sheets"
  add_foreign_key "adventures", "story_states"
  add_foreign_key "sheets", "users"
  add_foreign_key "story_states", "stories"
end
