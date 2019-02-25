# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2019_02_25_235135) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "day_pass_types", force: :cascade do |t|
    t.string "name", null: false
    t.integer "operator_id", null: false
    t.string "stripe_sku_id"
    t.integer "amount_in_cents", default: 0, null: false
    t.boolean "available", default: true, null: false
    t.boolean "visible", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "day_passes", force: :cascade do |t|
    t.date "day", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_charge_id"
    t.integer "operator_id", default: 1, null: false
    t.integer "day_pass_type_id"
    t.index ["operator_id"], name: "index_day_passes_on_operator_id"
  end

  create_table "door_punches", force: :cascade do |t|
    t.integer "door_id"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "operator_id", default: 1, null: false
    t.index ["operator_id"], name: "index_door_punches_on_operator_id"
  end

  create_table "doors", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.boolean "available", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "operator_id", default: 1, null: false
    t.index ["operator_id"], name: "index_doors_on_operator_id"
  end

  create_table "feed_items", force: :cascade do |t|
    t.integer "operator_id", null: false
    t.integer "user_id"
    t.jsonb "blob", default: "{}", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "expense", default: false, null: false
    t.index ["blob"], name: "index_feed_items_on_blob", using: :gin
  end

  create_table "friendly_id_slugs", id: :serial, force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_id"
    t.index ["sluggable_type"], name: "index_friendly_id_slugs_on_sluggable_type"
  end

  create_table "invoices", force: :cascade do |t|
    t.string "stripe_invoice_id"
    t.integer "user_id"
    t.integer "amount_due"
    t.integer "amount_paid"
    t.datetime "date"
    t.string "status"
    t.string "number"
    t.integer "operator_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "due_date"
  end

  create_table "member_feedbacks", force: :cascade do |t|
    t.boolean "anonymous", default: false, null: false
    t.text "comment"
    t.integer "rating"
    t.integer "operator_id", null: false
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "operators", force: :cascade do |t|
    t.string "name", null: false
    t.string "subdomain", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "snippet", default: "Generic snippet about the space", null: false
    t.string "wifi_name", default: "not set", null: false
    t.string "wifi_password", default: "not set", null: false
    t.string "building_address", default: "not set", null: false
    t.boolean "approval_required", default: true, null: false
    t.string "contact_name"
    t.string "contact_email"
    t.string "contact_phone"
    t.integer "day_pass_cost_in_cents", default: 2500, null: false
    t.integer "square_footage", default: 0, null: false
    t.boolean "email_enabled", default: false, null: false
    t.string "stripe_day_pass_product_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.integer "owner_id"
    t.string "website"
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "operator_id", default: 1, null: false
    t.index ["operator_id"], name: "index_organizations_on_operator_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "interval", null: false
    t.integer "amount_in_cents", null: false
    t.string "name", null: false
    t.boolean "visible", default: true, null: false
    t.boolean "available", default: true, null: false
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_plan_id"
    t.integer "operator_id", default: 1, null: false
    t.index ["operator_id"], name: "index_plans_on_operator_id"
  end

  create_table "reservations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.datetime "datetime_in", null: false
    t.integer "hours", default: 1, null: false
    t.integer "room_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rooms", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "whiteboard", default: false, null: false
    t.boolean "av", default: false, null: false
    t.integer "capacity", default: 1, null: false
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "visible", default: true, null: false
    t.integer "operator_id", default: 1, null: false
    t.index ["operator_id"], name: "index_rooms_on_operator_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "plan_id", null: false
    t.integer "user_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_subscription_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email", null: false
    t.string "password_digest"
    t.boolean "admin", default: false, null: false
    t.string "remember_digest"
    t.string "slug"
    t.text "bio"
    t.string "linkedin"
    t.string "twitter"
    t.string "website"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "organization_id"
    t.boolean "approved", default: false, null: false
    t.string "stripe_customer_id"
    t.integer "operator_id", default: 2, null: false
    t.boolean "superadmin", default: false, null: false
    t.boolean "out_of_band", default: false, null: false
    t.index ["operator_id"], name: "index_users_on_operator_id"
  end

end
