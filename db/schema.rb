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

ActiveRecord::Schema[7.2].define(version: 2026_08_25_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_stat_statements"
  enable_extension "plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
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
    t.datetime "created_at", precision: nil, null: false
    t.string "service_name", default: "amazon", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "operator_id", null: false
    t.string "kind", null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.jsonb "payload", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id", "kind", "occurred_at"], name: "index_activities_on_operator_id_and_kind_and_occurred_at"
    t.index ["subject_type", "subject_id"], name: "index_activities_on_subject_type_and_subject_id"
    t.index ["user_id", "kind", "occurred_at"], name: "index_activities_on_user_id_and_kind_and_occurred_at"
    t.index ["user_id", "occurred_at"], name: "index_activities_on_user_id_and_occurred_at"
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.bigint "visit_id"
    t.bigint "user_id"
    t.string "name"
    t.jsonb "properties"
    t.datetime "time", precision: nil
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.bigint "user_id"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.datetime "started_at", precision: nil
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
  end

  create_table "amenities", force: :cascade do |t|
    t.string "name"
    t.float "price", default: 0.0
    t.bigint "room_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "membership_price", default: 0.0
    t.index ["room_id"], name: "index_amenities_on_room_id"
  end

  create_table "amenities_reservations", id: false, force: :cascade do |t|
    t.bigint "reservation_id", null: false
    t.bigint "amenity_id", null: false
    t.index ["amenity_id", "reservation_id"], name: "index_amenities_reservations_on_amenity_id_and_reservation_id"
    t.index ["reservation_id", "amenity_id"], name: "index_amenities_reservations_on_reservation_id_and_amenity_id"
  end

  create_table "announcements", force: :cascade do |t|
    t.integer "user_id"
    t.text "body"
    t.integer "operator_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "location_id"
    t.index ["location_id"], name: "index_announcements_on_location_id"
  end

  create_table "automated_workflows", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "location_id"
    t.string "workflow_type", null: false
    t.boolean "enabled", default: false, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_automated_workflows_on_location_id"
    t.index ["operator_id", "location_id", "workflow_type"], name: "idx_workflows_operator_location_type", unique: true
    t.index ["operator_id"], name: "index_automated_workflows_on_operator_id"
  end

  create_table "beacons", force: :cascade do |t|
    t.string "name", null: false
    t.string "uuid", null: false
    t.integer "major", null: false
    t.integer "minor", null: false
    t.bigint "location_id", null: false
    t.bigint "door_id"
    t.integer "operator_id", default: 1, null: false
    t.datetime "last_seen_at"
    t.integer "battery_pct"
    t.datetime "installed_at"
    t.text "notes"
    t.boolean "available", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["door_id"], name: "index_beacons_on_door_id"
    t.index ["location_id"], name: "index_beacons_on_location_id"
    t.index ["operator_id", "uuid", "major", "minor"], name: "index_beacons_on_operator_uuid_major_minor", unique: true
    t.index ["operator_id"], name: "index_beacons_on_operator_id"
  end

  create_table "campaign_sends", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "campaign_step_id", null: false
    t.bigint "user_id", null: false
    t.string "status", default: "sent", null: false
    t.string "error_message"
    t.datetime "sent_at"
    t.boolean "opened", default: false
    t.datetime "opened_at"
    t.boolean "clicked", default: false
    t.datetime "clicked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_campaign_sends_on_campaign_id"
    t.index ["campaign_step_id", "user_id"], name: "index_campaign_sends_on_campaign_step_id_and_user_id", unique: true
    t.index ["campaign_step_id"], name: "index_campaign_sends_on_campaign_step_id"
    t.index ["user_id"], name: "index_campaign_sends_on_user_id"
  end

  create_table "campaign_steps", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.integer "position", default: 0, null: false
    t.string "subject", null: false
    t.text "body", null: false
    t.integer "delay_days", default: 0, null: false
    t.integer "sent_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "position"], name: "index_campaign_steps_on_campaign_id_and_position", unique: true
    t.index ["campaign_id"], name: "index_campaign_steps_on_campaign_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "location_id"
    t.string "name", null: false
    t.string "campaign_type", default: "single", null: false
    t.jsonb "segment", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.integer "recipient_count", default: 0
    t.datetime "scheduled_at"
    t.datetime "sent_at"
    t.integer "suppression_days", default: 7
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "cool_down_days", default: 30, null: false
    t.index ["location_id"], name: "index_campaigns_on_location_id"
    t.index ["operator_id"], name: "index_campaigns_on_operator_id"
  end

  create_table "checkins", force: :cascade do |t|
    t.integer "location_id", null: false
    t.integer "user_id", null: false
    t.timestamptz "datetime_in", null: false
    t.timestamptz "datetime_out"
    t.integer "invoice_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "billable_type"
    t.bigint "billable_id"
    t.index ["billable_type", "billable_id"], name: "index_checkins_on_billable_type_and_billable_id"
    t.index ["location_id"], name: "index_checkins_on_location_id"
  end

  create_table "child_profiles", force: :cascade do |t|
    t.string "name"
    t.datetime "birthday", precision: nil
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "childcare_reservations", force: :cascade do |t|
    t.integer "childcare_slot_id", null: false
    t.integer "child_profile_id", null: false
    t.date "date", null: false
    t.boolean "cancelled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "childcare_slots", force: :cascade do |t|
    t.string "name", null: false
    t.integer "week_day", null: false
    t.boolean "deleted", default: false, null: false
    t.integer "location_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "capacity", default: 0, null: false
  end

  create_table "comp_days", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "operator_id", null: false
    t.bigint "location_id", null: false
    t.bigint "granted_by_id"
    t.bigint "subscription_id"
    t.date "occurred_on", null: false
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["granted_by_id"], name: "index_comp_days_on_granted_by_id"
    t.index ["location_id"], name: "index_comp_days_on_location_id"
    t.index ["operator_id"], name: "index_comp_days_on_operator_id"
    t.index ["subscription_id"], name: "index_comp_days_on_subscription_id"
    t.index ["user_id", "location_id", "occurred_on"], name: "index_comp_days_on_user_id_and_location_id_and_occurred_on"
    t.index ["user_id"], name: "index_comp_days_on_user_id"
  end

  create_table "day_pass_bundle_redemptions", force: :cascade do |t|
    t.bigint "day_pass_bundle_id", null: false
    t.bigint "operator_id", default: 1, null: false
    t.string "kind", null: false
    t.bigint "performed_by_id"
    t.bigint "day_pass_id"
    t.string "guest_name"
    t.datetime "redeemed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "reservation_id"
    t.index ["day_pass_bundle_id"], name: "index_day_pass_bundle_redemptions_on_day_pass_bundle_id"
    t.index ["day_pass_id"], name: "index_day_pass_bundle_redemptions_on_day_pass_id"
    t.index ["performed_by_id"], name: "index_day_pass_bundle_redemptions_on_performed_by_id"
    t.index ["reservation_id"], name: "index_day_pass_bundle_redemptions_on_reservation_id"
  end

  create_table "day_pass_bundles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "day_pass_type_id", null: false
    t.bigint "location_id"
    t.bigint "operator_id", default: 1, null: false
    t.string "billable_type"
    t.bigint "billable_id"
    t.integer "quantity_purchased", null: false
    t.integer "passes_remaining", null: false
    t.datetime "expires_at"
    t.datetime "purchased_at", null: false
    t.bigint "invoice_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billable_type", "billable_id"], name: "index_day_pass_bundles_on_billable_type_and_billable_id"
    t.index ["day_pass_type_id"], name: "index_day_pass_bundles_on_day_pass_type_id"
    t.index ["invoice_id"], name: "index_day_pass_bundles_on_invoice_id"
    t.index ["location_id"], name: "index_day_pass_bundles_on_location_id"
    t.index ["operator_id"], name: "index_day_pass_bundles_on_operator_id"
    t.index ["user_id"], name: "index_day_pass_bundles_on_user_id"
  end

  create_table "day_pass_type_rooms", force: :cascade do |t|
    t.bigint "day_pass_type_id", null: false
    t.bigint "room_id", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day_pass_type_id", "position"], name: "index_dpt_rooms_on_type_and_position"
    t.index ["day_pass_type_id", "room_id"], name: "index_dpt_rooms_on_type_and_room", unique: true
    t.index ["room_id"], name: "index_day_pass_type_rooms_on_room_id"
  end

  create_table "day_pass_types", force: :cascade do |t|
    t.string "name", null: false
    t.integer "operator_id", null: false
    t.integer "amount_in_cents", default: 0, null: false
    t.boolean "available", default: true, null: false
    t.boolean "visible", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "always_allow_building_access", default: false, null: false
    t.string "code"
    t.integer "location_id"
    t.integer "included_meeting_room_minutes"
    t.integer "overage_rate_in_cents", default: 0, null: false
    t.boolean "default_for_room_booking", default: false, null: false
    t.integer "quantity", default: 1, null: false
    t.integer "expires_after_days"
    t.integer "daily_limit"
    t.string "kind", default: "standard", null: false
    t.index ["location_id"], name: "index_day_pass_types_on_location_id"
    t.index ["operator_id", "location_id", "default_for_room_booking"], name: "index_dpt_on_op_loc_default"
  end

  create_table "day_passes", force: :cascade do |t|
    t.date "day", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "stripe_charge_id"
    t.integer "operator_id", default: 1, null: false
    t.integer "day_pass_type_id"
    t.integer "invoice_id"
    t.string "billable_type"
    t.bigint "billable_id"
    t.integer "location_id"
    t.boolean "complimentary", default: false, null: false
    t.bigint "reservation_id"
    t.index ["billable_type", "billable_id"], name: "index_day_passes_on_billable_type_and_billable_id"
    t.index ["location_id"], name: "index_day_passes_on_location_id"
    t.index ["operator_id"], name: "index_day_passes_on_operator_id"
    t.index ["reservation_id"], name: "index_day_passes_on_reservation_id"
    t.index ["user_id", "day"], name: "index_day_passes_on_user_id_and_day"
  end

  create_table "discount_codes", force: :cascade do |t|
    t.string "code", null: false
    t.integer "operator_id", null: false
    t.integer "location_id"
    t.string "discount_type", null: false
    t.integer "discount_value", null: false
    t.string "applies_to", default: "all", null: false
    t.integer "max_redemptions"
    t.integer "redemption_count", default: 0, null: false
    t.datetime "expires_at"
    t.boolean "active", default: true, null: false
    t.string "stripe_coupon_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "duration", default: "once", null: false
    t.index ["operator_id", "code"], name: "index_discount_codes_on_operator_id_and_code", unique: true
    t.index ["operator_id", "location_id"], name: "index_discount_codes_on_operator_id_and_location_id"
  end

  create_table "discount_redemptions", force: :cascade do |t|
    t.bigint "discount_code_id", null: false
    t.bigint "user_id", null: false
    t.string "discountable_type"
    t.bigint "discountable_id"
    t.integer "discount_amount_in_cents", null: false
    t.integer "operator_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discount_code_id"], name: "index_discount_redemptions_on_discount_code_id"
    t.index ["discountable_type", "discountable_id"], name: "index_discount_redemptions_on_discountable"
    t.index ["operator_id"], name: "index_discount_redemptions_on_operator_id"
    t.index ["user_id"], name: "index_discount_redemptions_on_user_id"
  end

  create_table "door_punches", force: :cascade do |t|
    t.integer "door_id"
    t.integer "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "operator_id", default: 1, null: false
    t.jsonb "json"
    t.string "method", default: "manual", null: false
    t.string "status", default: "unlocked", null: false
    t.boolean "room_entry", default: false, null: false
    t.index ["method"], name: "index_door_punches_on_method"
    t.index ["operator_id"], name: "index_door_punches_on_operator_id"
    t.index ["status"], name: "index_door_punches_on_status"
  end

  create_table "doors", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.boolean "available", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "operator_id", default: 1, null: false
    t.integer "kisi_id"
    t.bigint "location_id"
    t.boolean "private", default: false, null: false
    t.bigint "room_id"
    t.index ["location_id"], name: "index_doors_on_location_id"
    t.index ["operator_id"], name: "index_doors_on_operator_id"
    t.index ["room_id"], name: "index_doors_on_room_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "title", null: false
    t.text "description"
    t.integer "user_id", null: false
    t.integer "location_id", null: false
    t.datetime "starts_at", precision: nil, null: false
    t.string "location_string"
    t.datetime "ends_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "approved_at"
    t.datetime "rejected_at"
    t.boolean "submitted_via_app", default: false, null: false
    t.index ["approved_at"], name: "index_events_on_approved_at"
  end

  create_table "feed_item_comments", force: :cascade do |t|
    t.integer "feed_item_id", null: false
    t.integer "user_id", null: false
    t.text "comment"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "feed_items", force: :cascade do |t|
    t.integer "operator_id", null: false
    t.integer "user_id"
    t.jsonb "blob", default: "{}", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "expense", default: false, null: false
    t.integer "location_id"
    t.index ["blob"], name: "index_feed_items_on_blob", using: :gin
    t.index ["location_id"], name: "index_feed_items_on_location_id"
    t.index ["operator_id", "updated_at"], name: "index_feed_items_on_operator_id_and_updated_at"
  end

  create_table "feedback_replies", force: :cascade do |t|
    t.bigint "member_feedback_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.integer "operator_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_feedback_id"], name: "index_feedback_replies_on_member_feedback_id"
    t.index ["operator_id"], name: "index_feedback_replies_on_operator_id"
    t.index ["user_id"], name: "index_feedback_replies_on_user_id"
  end

  create_table "friendly_id_slugs", id: :serial, force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at", precision: nil
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_id"
    t.index ["sluggable_type"], name: "index_friendly_id_slugs_on_sluggable_type"
  end

  create_table "interest_tags", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "operator_id", null: false
    t.string "product", null: false
    t.string "source", null: false
    t.bigint "added_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_purchased_at"
    t.index ["added_by_id"], name: "index_interest_tags_on_added_by_id"
    t.index ["operator_id", "product"], name: "index_interest_tags_on_operator_id_and_product"
    t.index ["operator_id"], name: "index_interest_tags_on_operator_id"
    t.index ["user_id", "product"], name: "index_interest_tags_on_user_id_and_product", unique: true
    t.index ["user_id"], name: "index_interest_tags_on_user_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.string "stripe_invoice_id"
    t.integer "amount_due"
    t.integer "amount_paid"
    t.datetime "date", precision: nil
    t.string "status"
    t.string "number"
    t.integer "operator_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "due_date", precision: nil
    t.string "billable_type"
    t.bigint "billable_id"
    t.integer "location_id"
    t.string "stripe_payment_intent_id"
    t.string "description"
    t.datetime "refunded_at"
    t.integer "refund_amount_in_cents"
    t.bigint "reservation_id"
    t.index ["billable_type", "billable_id"], name: "index_invoices_on_billable_type_and_billable_id"
    t.index ["location_id"], name: "index_invoices_on_location_id"
    t.index ["reservation_id"], name: "index_invoices_on_reservation_id"
    t.index ["stripe_invoice_id"], name: "index_invoices_on_stripe_invoice_id"
    t.index ["stripe_payment_intent_id"], name: "index_invoices_on_stripe_payment_intent_id"
  end

  create_table "lead_notes", force: :cascade do |t|
    t.integer "lead_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "leads", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "ahoy_visit_id"
    t.string "status"
    t.integer "operator_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source"
  end

  create_table "lease_renewal_requests", force: :cascade do |t|
    t.bigint "office_lease_id", null: false
    t.bigint "operator_id", null: false
    t.bigint "location_id"
    t.integer "proposed_price_in_cents", null: false
    t.integer "current_price_in_cents", null: false
    t.date "proposed_start_date", null: false
    t.date "proposed_end_date", null: false
    t.string "escalation_applied"
    t.string "status", default: "pending_leasee", null: false
    t.text "leasee_notes"
    t.text "admin_notes"
    t.datetime "leasee_responded_at"
    t.datetime "admin_responded_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_lease_renewal_requests_on_location_id"
    t.index ["office_lease_id", "status"], name: "index_lease_renewal_requests_on_office_lease_id_and_status"
    t.index ["office_lease_id"], name: "index_lease_renewal_requests_on_office_lease_id"
    t.index ["operator_id"], name: "index_lease_renewal_requests_on_operator_id"
  end

  create_table "location_events", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "location_id"
    t.date "date", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_location_events_on_location_id"
    t.index ["operator_id"], name: "index_location_events_on_operator_id"
  end

  create_table "location_managements", force: :cascade do |t|
    t.bigint "location_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_location_managements_on_location_id"
    t.index ["user_id"], name: "index_location_managements_on_user_id"
  end

  create_table "location_resources", id: :serial, force: :cascade do |t|
  end

  create_table "locations", force: :cascade do |t|
    t.string "name"
    t.bigint "operator_id"
    t.string "billing_state"
    t.string "building_address"
    t.string "city"
    t.string "state"
    t.string "zip"
    t.string "contact_email"
    t.string "contact_name"
    t.string "contact_phone"
    t.string "snippet"
    t.integer "square_footage"
    t.string "stripe_access_token"
    t.string "stripe_publishable_key"
    t.string "stripe_refresh_token"
    t.string "wifi_name"
    t.string "wifi_password"
    t.string "working_day_start", default: "09:00", null: false
    t.string "working_day_end", default: "18:00", null: false
    t.string "stripe_user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "time_zone", default: "Pacific Time (US & Canada)", null: false
    t.boolean "visible", default: true, null: false
    t.integer "flex_square_footage", default: 0, null: false
    t.integer "common_square_footage", default: 0, null: false
    t.string "building_access_instructions"
    t.boolean "allow_hourly", default: false, null: false
    t.integer "hourly_rate_in_cents", default: 0, null: false
    t.boolean "new_users_get_free_day_pass", default: false, null: false
    t.boolean "open_sunday", default: false, null: false
    t.boolean "open_monday", default: true, null: false
    t.boolean "open_tuesday", default: true, null: false
    t.boolean "open_wednesday", default: true, null: false
    t.boolean "open_thursday", default: true, null: false
    t.boolean "open_friday", default: true, null: false
    t.boolean "open_saturday", default: false, null: false
    t.integer "credit_cost_in_cents", default: 0, null: false
    t.integer "childcare_reservation_cost_in_cents", default: 0, null: false
    t.string "kisi_api_key"
    t.boolean "announcements_enabled", default: true, null: false
    t.boolean "events_enabled", default: true, null: false
    t.boolean "door_integration_enabled", default: true, null: false
    t.boolean "rooms_enabled", default: true, null: false
    t.boolean "offices_enabled", default: false, null: false
    t.boolean "bulletin_board_enabled", default: false, null: false
    t.boolean "credits_enabled", default: false, null: false
    t.boolean "childcare_enabled", default: false, null: false
    t.boolean "crm_enabled", default: true, null: false
    t.string "sender_email"
    t.string "google_reviews_url"
    t.integer "renewal_reminder_days"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.integer "past_member_grace_days", default: 180, null: false
    t.bigint "space_host_id"
    t.string "day_pass_period_start", default: "04:00", null: false
    t.integer "overage_rate_in_cents", default: 0, null: false
    t.text "pause_warning"
    t.index ["operator_id"], name: "index_locations_on_operator_id"
    t.index ["space_host_id"], name: "index_locations_on_space_host_id"
    t.index ["state", "city"], name: "index_locations_on_state_and_city"
    t.index ["zip"], name: "index_locations_on_zip"
  end

  create_table "locations_plans", id: false, force: :cascade do |t|
    t.bigint "plan_id"
    t.bigint "location_id"
    t.index ["location_id"], name: "index_locations_plans_on_location_id"
    t.index ["plan_id"], name: "index_locations_plans_on_plan_id"
  end

  create_table "member_feedbacks", force: :cascade do |t|
    t.boolean "anonymous", default: false, null: false
    t.text "comment"
    t.integer "rating"
    t.integer "operator_id", null: false
    t.integer "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "location_id"
    t.datetime "last_read_at"
    t.datetime "dismissed_at"
    t.index ["location_id"], name: "index_member_feedbacks_on_location_id"
  end

  create_table "notes", force: :cascade do |t|
    t.string "notable_type", null: false
    t.bigint "notable_id", null: false
    t.bigint "operator_id", null: false
    t.bigint "author_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source_type"
    t.bigint "source_id"
    t.index ["author_id"], name: "index_notes_on_author_id"
    t.index ["notable_type", "notable_id"], name: "index_notes_on_notable"
    t.index ["operator_id", "created_at"], name: "index_notes_on_operator_id_and_created_at"
    t.index ["operator_id"], name: "index_notes_on_operator_id"
    t.index ["source_type", "source_id"], name: "index_notes_on_source"
  end

  create_table "office_leases", force: :cascade do |t|
    t.bigint "operator_id"
    t.bigint "organization_id"
    t.bigint "office_id"
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "subscription_id"
    t.date "initial_invoice_date"
    t.boolean "always_allow_building_access", default: true, null: false
    t.bigint "location_id"
    t.bigint "user_id"
    t.integer "deposit_amount_in_cents", default: 0, null: false
    t.boolean "auto_renew", default: false, null: false
    t.integer "renewal_notice_days", default: 60, null: false
    t.string "escalation_type"
    t.decimal "escalation_value", precision: 10, scale: 2
    t.string "cpi_index_series_id"
    t.datetime "deposit_invoiced_at"
    t.datetime "renewal_notice_sent_at"
    t.index ["location_id"], name: "index_office_leases_on_location_id"
    t.index ["office_id"], name: "index_office_leases_on_office_id"
    t.index ["operator_id"], name: "index_office_leases_on_operator_id"
    t.index ["organization_id"], name: "index_office_leases_on_organization_id"
    t.index ["subscription_id"], name: "index_office_leases_on_subscription_id"
    t.index ["user_id"], name: "index_office_leases_on_user_id"
  end

  create_table "officernd_imports", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "location_id"
    t.bigint "created_by_id"
    t.string "kind", default: "members", null: false
    t.string "status", default: "pending", null: false
    t.string "amount_format", default: "dollars", null: false
    t.jsonb "headers", default: [], null: false
    t.jsonb "column_mapping", default: {}, null: false
    t.jsonb "plan_mapping", default: {}, null: false
    t.integer "row_count", default: 0, null: false
    t.jsonb "result_log", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_officernd_imports_on_location_id"
    t.index ["operator_id"], name: "index_officernd_imports_on_operator_id"
  end

  create_table "offices", force: :cascade do |t|
    t.bigint "operator_id"
    t.string "name"
    t.string "slug"
    t.integer "capacity", default: 1, null: false
    t.boolean "visible", default: true, null: false
    t.text "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "location_id"
    t.integer "square_footage", default: 0, null: false
    t.index ["location_id"], name: "index_offices_on_location_id"
    t.index ["operator_id"], name: "index_offices_on_operator_id"
  end

  create_table "operator_surveys", force: :cascade do |t|
    t.integer "user_id"
    t.integer "operator_id"
    t.integer "square_footage"
    t.integer "number_of_members"
    t.string "space_name"
    t.string "operator_name"
    t.string "operator_email"
    t.string "location"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "operators", force: :cascade do |t|
    t.string "name", null: false
    t.string "subdomain", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
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
    t.string "kisi_api_key"
    t.string "stripe_user_id"
    t.string "stripe_publishable_key"
    t.string "stripe_refresh_token"
    t.string "stripe_access_token"
    t.string "billing_state", default: "demo", null: false
    t.string "ios_url"
    t.string "android_url"
    t.boolean "checkin_required", default: false, null: false
    t.string "membership_text"
    t.boolean "skip_onboarding", default: false, null: false
    t.boolean "announcements_enabled", default: true, null: false
    t.boolean "events_enabled", default: true, null: false
    t.boolean "door_integration_enabled", default: true, null: false
    t.boolean "rooms_enabled", default: true, null: false
    t.boolean "offices_enabled", default: true, null: false
    t.boolean "reservation_notifications", default: false, null: false
    t.boolean "membership_notifications", default: true, null: false
    t.boolean "signup_notifications", default: false, null: false
    t.boolean "day_pass_notifications", default: true, null: false
    t.boolean "member_feedback_notifications", default: true, null: false
    t.boolean "checkin_notifications", default: true, null: false
    t.boolean "refund_notifications", default: true, null: false
    t.boolean "post_notifications", default: true, null: false
    t.boolean "credits_enabled", default: false, null: false
    t.boolean "childcare_enabled", default: false, null: false
    t.boolean "bulletin_board_enabled", default: false, null: false
    t.string "android_server_key"
    t.boolean "crm_enabled", default: false, null: false
    t.string "bundle_id"
    t.string "firebase_project_id"
    t.string "sender_email"
    t.string "google_reviews_url"
    t.integer "renewal_reminder_days", default: 7
    t.boolean "paid_room_reservation_notifications", default: true, null: false
    t.string "mailchimp_api_key"
    t.string "mailchimp_audience_id"
    t.datetime "last_activities_backfilled_at"
    t.integer "refund_fee_percent", default: 0, null: false
    t.integer "cancellation_window_hours", default: 24, null: false
    t.boolean "tour_widget_enabled", default: false, null: false
    t.string "tour_widget_thank_you_url"
    t.string "primary_color"
    t.string "accent_color"
    t.datetime "mobile_app_requested_at"
    t.integer "commitment_notice_days", default: 30, null: false
    t.boolean "concierge_enabled", default: false, null: false
    t.string "concierge_assistant_name"
    t.string "concierge_greeting"
    t.string "concierge_offer_text"
    t.string "concierge_promo_code"
    t.string "concierge_off_hours_message"
    t.string "embed_font"
    t.string "embed_accent_override"
    t.integer "building_access_window_minutes", default: 60, null: false
    t.index ["subdomain"], name: "index_operators_on_subdomain", unique: true
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.integer "owner_id"
    t.string "website"
    t.string "slug"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "operator_id", default: 1, null: false
    t.string "stripe_customer_id"
    t.boolean "out_of_band", default: false, null: false
    t.integer "billing_contact_id"
    t.boolean "visible", default: true, null: false
    t.integer "location_id"
    t.index ["location_id"], name: "index_organizations_on_location_id"
    t.index ["operator_id"], name: "index_organizations_on_operator_id"
  end

  create_table "plan_categories", force: :cascade do |t|
    t.string "name"
    t.integer "operator_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "location_id"
    t.index ["location_id"], name: "index_plan_categories_on_location_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "interval", null: false
    t.integer "amount_in_cents", null: false
    t.string "name", null: false
    t.boolean "visible", default: true, null: false
    t.boolean "available", default: true, null: false
    t.string "slug"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "stripe_plan_id"
    t.integer "operator_id", default: 1, null: false
    t.string "plan_type"
    t.boolean "always_allow_building_access", default: true, null: false
    t.boolean "has_day_limit", default: false, null: false
    t.integer "day_limit", default: 0, null: false
    t.integer "credits", default: 0, null: false
    t.integer "commitment_interval"
    t.integer "childcare_reservations", default: 0, null: false
    t.integer "plan_category_id"
    t.integer "location_id"
    t.integer "included_meeting_room_minutes"
    t.integer "overage_rate_in_cents", default: 0
    t.integer "building_access_level", default: 1, null: false
    t.index ["location_id"], name: "index_plans_on_location_id"
    t.index ["operator_id"], name: "index_plans_on_operator_id"
  end

  create_table "post_reactions", force: :cascade do |t|
    t.bigint "post_id", null: false
    t.bigint "user_id", null: false
    t.string "emoji", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id", "user_id", "emoji"], name: "index_post_reactions_unique", unique: true
    t.index ["post_id"], name: "index_post_reactions_on_post_id"
    t.index ["user_id"], name: "index_post_reactions_on_user_id"
  end

  create_table "post_replies", force: :cascade do |t|
    t.integer "post_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "posts", force: :cascade do |t|
    t.integer "location_id", null: false
    t.integer "user_id", null: false
    t.string "title", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_posts_on_location_id"
  end

  create_table "product_email_sends", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "user_id", null: false
    t.string "sendable_type", null: false
    t.bigint "sendable_id", null: false
    t.string "email_type", null: false
    t.string "status", default: "sent"
    t.text "error_message"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id"], name: "index_product_email_sends_on_operator_id"
    t.index ["sendable_type", "sendable_id", "email_type"], name: "idx_product_email_sends_unique", unique: true
    t.index ["user_id"], name: "index_product_email_sends_on_user_id"
  end

  create_table "product_email_templates", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.string "product_type", null: false
    t.string "email_type", null: false
    t.string "subject", null: false
    t.boolean "enabled", default: false
    t.integer "follow_up_delay_days"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "location_id"
    t.index ["location_id"], name: "index_product_email_templates_on_location_id"
    t.index ["operator_id", "location_id", "product_type", "email_type"], name: "idx_pet_operator_location_product_email", unique: true
    t.index ["operator_id"], name: "index_product_email_templates_on_operator_id"
  end

  create_table "recurring_reservations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "room_id", null: false
    t.string "title", null: false
    t.string "recurrence_pattern", null: false
    t.integer "duration_minutes", null: false
    t.time "time_of_day", null: false
    t.integer "day_of_week"
    t.integer "day_of_month"
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.boolean "cancelled", default: false, null: false
    t.integer "operator_id", null: false
    t.bigint "location_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id"], name: "index_recurring_reservations_on_operator_id"
    t.index ["room_id"], name: "index_recurring_reservations_on_room_id"
    t.index ["user_id"], name: "index_recurring_reservations_on_user_id"
  end

  create_table "refunds", force: :cascade do |t|
    t.bigint "invoice_id"
    t.string "stripe_refund_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "amount", default: 0, null: false
    t.index ["invoice_id"], name: "index_refunds_on_invoice_id"
  end

  create_table "reservations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.timestamptz "datetime_in", null: false
    t.integer "hours", default: 1, null: false
    t.integer "room_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "cancelled", default: false, null: false
    t.integer "minutes", default: 0, null: false
    t.integer "credit_cost", default: 0, null: false
    t.boolean "ended_early", default: false
    t.boolean "paid"
    t.text "note"
    t.bigint "recurring_reservation_id"
    t.string "stripe_payment_intent_id"
    t.integer "authorized_amount_in_cents"
    t.integer "captured_amount_in_cents"
    t.datetime "captured_at"
    t.datetime "payment_failed_at"
    t.datetime "arrival_notified_at"
    t.datetime "started_notified_at"
    t.integer "attendee_count"
    t.bigint "day_office_pass_id"
    t.index ["day_office_pass_id"], name: "index_reservations_on_day_office_pass_id"
    t.index ["recurring_reservation_id"], name: "index_reservations_on_recurring_reservation_id"
    t.index ["room_id", "datetime_in"], name: "index_reservations_on_room_id_and_datetime_in"
    t.index ["stripe_payment_intent_id"], name: "index_reservations_on_stripe_payment_intent_id", unique: true
    t.index ["user_id", "datetime_in"], name: "index_reservations_on_user_id_and_datetime_in"
  end

  create_table "room_demand_misses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "operator_id", null: false
    t.bigint "location_id", null: false
    t.datetime "missed_at", null: false
    t.integer "day_of_week"
    t.integer "hour_of_day"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id", "day_of_week", "hour_of_day"], name: "idx_demand_misses_heatmap"
    t.index ["location_id", "missed_at"], name: "index_room_demand_misses_on_location_id_and_missed_at"
    t.index ["location_id"], name: "index_room_demand_misses_on_location_id"
    t.index ["operator_id"], name: "index_room_demand_misses_on_operator_id"
    t.index ["user_id"], name: "index_room_demand_misses_on_user_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "capacity", default: 1, null: false
    t.string "slug"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "visible", default: true, null: false
    t.integer "operator_id", default: 1, null: false
    t.bigint "location_id"
    t.integer "square_footage", default: 0, null: false
    t.boolean "rentable", default: false, null: false
    t.integer "hourly_rate_in_cents", default: 0, null: false
    t.integer "credit_cost", default: 0, null: false
    t.boolean "allow_shorter_reservation_duration", default: true, null: false
    t.text "features", default: [], array: true
    t.boolean "archived", default: false, null: false
    t.boolean "include_with_day_pass", default: false, null: false
    t.index ["archived"], name: "index_rooms_on_archived"
    t.index ["location_id"], name: "index_rooms_on_location_id"
    t.index ["operator_id"], name: "index_rooms_on_operator_id"
  end

  create_table "rsvps", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "event_id", null: false
    t.boolean "going", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "ahoy_visit_id"
  end

  create_table "subdomains", force: :cascade do |t|
    t.string "subdomain", null: false
    t.boolean "in_use", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "plan_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "stripe_subscription_id"
    t.string "subscribable_type"
    t.bigint "subscribable_id"
    t.boolean "pending", default: false, null: false
    t.string "billable_type"
    t.bigint "billable_id"
    t.date "start_date", null: false
    t.boolean "cancelling_at_end_of_billing_period", default: false, null: false
    t.boolean "paused", default: false, null: false
    t.index ["billable_type", "billable_id"], name: "index_subscriptions_on_billable_type_and_billable_id"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id"
    t.index ["subscribable_type", "subscribable_id"], name: "index_subscriptions_on_subscribable_type_and_subscribable_id"
  end

  create_table "tracking_pixels", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "location_id", null: false
    t.string "name"
    t.string "script"
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "always_on", default: false, null: false
    t.index ["location_id"], name: "index_tracking_pixels_on_location_id"
    t.index ["operator_id"], name: "index_tracking_pixels_on_operator_id"
    t.index ["position"], name: "index_tracking_pixels_on_position"
  end

  create_table "user_payment_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "location_id", null: false
    t.string "stripe_customer_id"
    t.boolean "card_added", default: false, null: false
    t.boolean "bill_to_organization", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_user_payment_profiles_on_location_id"
    t.index ["user_id", "location_id"], name: "index_user_payment_profiles_on_user_id_and_location_id", unique: true
    t.index ["user_id"], name: "index_user_payment_profiles_on_user_id"
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
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "organization_id"
    t.boolean "approved", default: false, null: false
    t.string "stripe_customer_id"
    t.integer "operator_id", default: 2, null: false
    t.boolean "superadmin", default: false, null: false
    t.boolean "out_of_band", default: false, null: false
    t.string "ios_token"
    t.string "reset_digest"
    t.datetime "reset_sent_at", precision: nil
    t.boolean "card_added", default: false, null: false
    t.boolean "always_allow_building_access", default: false, null: false
    t.boolean "bill_to_organization", default: false, null: false
    t.boolean "archived", default: false, null: false
    t.string "phone"
    t.integer "credit_balance", default: 0, null: false
    t.integer "childcare_reservation_balance", default: 0, null: false
    t.string "android_token"
    t.string "role", default: "unassigned", null: false
    t.integer "original_location_id"
    t.integer "current_location_id"
    t.boolean "email_confirmed", default: false, null: false
    t.string "confirmation_token"
    t.datetime "confirmation_sent_at"
    t.boolean "marketing_consent", default: false, null: false
    t.datetime "terms_accepted_at"
    t.bigint "preferred_room_id"
    t.integer "preferred_meeting_duration", default: 60
    t.datetime "last_active_at"
    t.boolean "email_opted_out", default: false, null: false
    t.boolean "email_bounced", default: false, null: false
    t.boolean "marketing_suppressed", default: false, null: false
    t.string "marketing_suppressed_reason"
    t.datetime "inactive_dismissed_at"
    t.bigint "point_of_contact_id"
    t.decimal "home_latitude", precision: 10, scale: 7
    t.decimal "home_longitude", precision: 10, scale: 7
    t.string "home_city"
    t.string "home_state"
    t.string "home_zip"
    t.string "login_code_digest"
    t.datetime "login_code_sent_at"
    t.integer "login_code_attempts", default: 0, null: false
    t.index "operator_id, lower((email)::text)", name: "index_users_on_operator_id_and_lower_email", unique: true
    t.index ["home_state", "home_city"], name: "index_users_on_home_state_and_home_city"
    t.index ["home_zip"], name: "index_users_on_home_zip"
    t.index ["operator_id", "home_state", "home_city"], name: "index_users_on_operator_home_state_home_city"
    t.index ["operator_id"], name: "index_users_on_operator_id"
    t.index ["point_of_contact_id"], name: "index_users_on_point_of_contact_id"
    t.index ["preferred_room_id"], name: "index_users_on_preferred_room_id"
  end

  create_table "weekly_updates", force: :cascade do |t|
    t.integer "operator_id"
    t.jsonb "blob"
    t.datetime "week_start", precision: nil
    t.datetime "week_end", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "previous_blob"
    t.integer "location_id"
    t.index ["location_id", "week_start"], name: "idx_weekly_updates_location_week_unique", unique: true
    t.index ["location_id"], name: "index_weekly_updates_on_location_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activities", "operators"
  add_foreign_key "activities", "users"
  add_foreign_key "amenities", "rooms"
  add_foreign_key "amenities_reservations", "amenities"
  add_foreign_key "amenities_reservations", "reservations"
  add_foreign_key "beacons", "doors"
  add_foreign_key "beacons", "locations"
  add_foreign_key "campaign_sends", "campaign_steps"
  add_foreign_key "campaign_sends", "campaigns"
  add_foreign_key "campaign_steps", "campaigns"
  add_foreign_key "comp_days", "locations"
  add_foreign_key "comp_days", "subscriptions"
  add_foreign_key "comp_days", "users"
  add_foreign_key "comp_days", "users", column: "granted_by_id"
  add_foreign_key "day_pass_bundle_redemptions", "users", column: "performed_by_id"
  add_foreign_key "day_pass_type_rooms", "day_pass_types"
  add_foreign_key "day_pass_type_rooms", "rooms"
  add_foreign_key "day_passes", "reservations", on_delete: :nullify
  add_foreign_key "discount_redemptions", "discount_codes"
  add_foreign_key "discount_redemptions", "users"
  add_foreign_key "doors", "locations"
  add_foreign_key "doors", "rooms"
  add_foreign_key "feedback_replies", "member_feedbacks"
  add_foreign_key "feedback_replies", "users"
  add_foreign_key "interest_tags", "operators"
  add_foreign_key "interest_tags", "users"
  add_foreign_key "interest_tags", "users", column: "added_by_id"
  add_foreign_key "lease_renewal_requests", "locations"
  add_foreign_key "lease_renewal_requests", "office_leases"
  add_foreign_key "lease_renewal_requests", "operators"
  add_foreign_key "location_managements", "locations"
  add_foreign_key "location_managements", "users"
  add_foreign_key "notes", "operators"
  add_foreign_key "notes", "users", column: "author_id"
  add_foreign_key "office_leases", "locations", on_delete: :nullify
  add_foreign_key "office_leases", "offices", on_delete: :nullify
  add_foreign_key "office_leases", "operators", on_delete: :nullify
  add_foreign_key "office_leases", "organizations", on_delete: :nullify
  add_foreign_key "office_leases", "subscriptions", on_delete: :nullify
  add_foreign_key "office_leases", "users"
  add_foreign_key "offices", "locations", on_delete: :nullify
  add_foreign_key "post_reactions", "posts"
  add_foreign_key "post_reactions", "users"
  add_foreign_key "product_email_sends", "operators"
  add_foreign_key "product_email_sends", "users"
  add_foreign_key "product_email_templates", "locations"
  add_foreign_key "product_email_templates", "operators"
  add_foreign_key "refunds", "invoices", on_delete: :nullify
  add_foreign_key "reservations", "day_passes", column: "day_office_pass_id", on_delete: :nullify
  add_foreign_key "room_demand_misses", "locations"
  add_foreign_key "room_demand_misses", "operators"
  add_foreign_key "room_demand_misses", "users"
  add_foreign_key "rooms", "locations"
  add_foreign_key "tracking_pixels", "locations"
  add_foreign_key "tracking_pixels", "operators"
  add_foreign_key "user_payment_profiles", "locations"
  add_foreign_key "user_payment_profiles", "users"
  add_foreign_key "users", "users", column: "point_of_contact_id"
end
