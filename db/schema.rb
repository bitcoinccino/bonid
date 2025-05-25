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

ActiveRecord::Schema[8.0].define(version: 2025_05_25_125924) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.string "street_address"
    t.bigint "communal_section_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "postal_code"
    t.string "locality"
    t.string "country"
    t.bigint "commune_id"
    t.float "latitude"
    t.float "longitude"
    t.bigint "partner_id"
    t.string "addressable_type"
    t.bigint "addressable_id"
    t.index ["addressable_type", "addressable_id"], name: "index_addresses_on_addressable"
    t.index ["communal_section_id"], name: "index_addresses_on_communal_section_id"
    t.index ["partner_id"], name: "index_addresses_on_partner_id"
  end

  create_table "arrondissements", force: :cascade do |t|
    t.string "name"
    t.integer "postal_code_digit"
    t.bigint "department_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "code"
    t.index ["department_id"], name: "index_arrondissements_on_department_id"
    t.index ["name"], name: "index_arrondissements_on_name"
  end

  create_table "communal_sections", force: :cascade do |t|
    t.string "name"
    t.integer "postal_code_digit"
    t.bigint "commune_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "pcode"
    t.string "postal_code"
    t.index ["commune_id"], name: "index_communal_sections_on_commune_id"
    t.index ["name"], name: "index_communal_sections_on_name"
  end

  create_table "communes", force: :cascade do |t|
    t.string "name"
    t.integer "postal_code_digit"
    t.bigint "arrondissement_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "code"
    t.string "postal_code"
    t.bigint "department_id", null: false
    t.index ["arrondissement_id"], name: "index_communes_on_arrondissement_id"
    t.index ["department_id"], name: "index_communes_on_department_id"
    t.index ["name"], name: "index_communes_on_name"
  end

  create_table "departments", force: :cascade do |t|
    t.string "name"
    t.integer "postal_code_prefix"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug"
    t.index ["name"], name: "index_departments_on_name", unique: true
    t.index ["slug"], name: "index_departments_on_slug", unique: true
  end

  create_table "identity_submissions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.datetime "expires_at"
    t.string "verification_token"
    t.text "rejection_reason"
    t.boolean "reset_requested"
    t.datetime "reset_requested_at"
    t.string "reset_request_status"
    t.text "reset_rejection_reason"
    t.datetime "reissued_at"
    t.text "reset_rejection_notes"
    t.string "additional_proof_type"
    t.string "reason"
    t.string "other_reason"
    t.text "qr_png_base64"
    t.string "submission_type"
    t.string "id_type"
    t.integer "staged_for", default: 0, null: false
    t.bigint "partner_id", null: false
    t.index ["partner_id"], name: "index_identity_submissions_on_partner_id"
    t.index ["user_id"], name: "index_identity_submissions_on_user_id"
  end

  create_table "incident_reports", force: :cascade do |t|
    t.bigint "officer_id", null: false
    t.string "crime_type"
    t.text "description"
    t.datetime "occurred_at"
    t.bigint "address_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status"
    t.text "review_comment"
    t.integer "reviewed_by_id"
    t.string "report_id"
    t.string "suspect_name"
    t.string "suspect_bonid"
    t.string "suspect_status"
    t.string "officer_name"
    t.string "officer_bonid"
    t.string "officer_unit"
    t.datetime "submitted_at"
    t.string "bonid_case_number"
    t.string "qr_code"
    t.bigint "suspect_user_id"
    t.index ["address_id"], name: "index_incident_reports_on_address_id"
    t.index ["bonid_case_number"], name: "index_incident_reports_on_bonid_case_number"
    t.index ["officer_bonid"], name: "index_incident_reports_on_officer_bonid"
    t.index ["officer_id"], name: "index_incident_reports_on_officer_id"
    t.index ["report_id"], name: "index_incident_reports_on_report_id", unique: true
    t.index ["suspect_bonid"], name: "index_incident_reports_on_suspect_bonid"
  end

  create_table "officers", force: :cascade do |t|
    t.string "full_name", null: false
    t.string "badge_id", null: false
    t.string "rank"
    t.string "unit_name"
    t.string "unit_type"
    t.bigint "partner_id", null: false
    t.bigint "department_id"
    t.bigint "arrondissement_id"
    t.bigint "commune_id"
    t.bigint "communal_section_id"
    t.string "email", null: false
    t.string "phone_number"
    t.boolean "approved", default: false
    t.datetime "invited_at"
    t.datetime "approved_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status"
    t.integer "role"
    t.string "invitation_token"
    t.datetime "invitation_accepted_at"
    t.bigint "user_id"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.index ["arrondissement_id"], name: "index_officers_on_arrondissement_id"
    t.index ["badge_id"], name: "index_officers_on_badge_id", unique: true
    t.index ["communal_section_id"], name: "index_officers_on_communal_section_id"
    t.index ["commune_id"], name: "index_officers_on_commune_id"
    t.index ["department_id"], name: "index_officers_on_department_id"
    t.index ["email"], name: "index_officers_on_email", unique: true
    t.index ["partner_id"], name: "index_officers_on_partner_id"
    t.index ["reset_password_token"], name: "index_officers_on_reset_password_token"
    t.index ["user_id"], name: "index_officers_on_user_id"
  end

  create_table "partner_applications", force: :cascade do |t|
    t.string "organization_name"
    t.string "contact_person"
    t.string "email"
    t.string "phone_number"
    t.string "department_sector"
    t.string "website"
    t.string "human_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "approved"
    t.string "contact_code"
    t.string "use_cases", default: [], array: true
    t.string "rejection_reason"
    t.bigint "partner_id"
    t.text "description"
    t.string "unit_name"
    t.string "unit_type"
    t.index ["partner_id"], name: "index_partner_applications_on_partner_id"
  end

  create_table "partners", force: :cascade do |t|
    t.string "name"
    t.string "contact_person"
    t.string "email"
    t.string "sector"
    t.string "slug"
    t.datetime "verified_at"
    t.string "use_cases", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "website"
    t.string "communal_section"
    t.string "street_address"
    t.string "postal_code"
    t.string "commune"
    t.string "department"
    t.string "country"
    t.float "latitude"
    t.float "longitude"
    t.text "description"
    t.bigint "partner_application_id"
    t.string "phone_number"
  end

  create_table "qr_scan_logs", force: :cascade do |t|
    t.bigint "qr_scan_id", null: false
    t.bigint "partner_id"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["partner_id"], name: "index_qr_scan_logs_on_partner_id"
    t.index ["qr_scan_id"], name: "index_qr_scan_logs_on_qr_scan_id"
  end

  create_table "qr_scans", force: :cascade do |t|
    t.bigint "identity_submission_id", null: false
    t.datetime "scanned_at"
    t.string "user_agent"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "verified_by"
    t.string "country"
    t.string "city"
    t.string "region"
    t.string "organization"
    t.bigint "partner_id", null: false
    t.index ["identity_submission_id"], name: "index_qr_scans_on_identity_submission_id"
    t.index ["partner_id"], name: "index_qr_scans_on_partner_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "id_number"
    t.string "first_name"
    t.string "middle_name"
    t.string "last_name"
    t.date "dob"
    t.string "phone"
    t.string "social_handle"
    t.string "street_address"
    t.string "postal_code"
    t.string "locality"
    t.string "country"
    t.string "place_of_birth"
    t.string "nationality"
    t.date "id_issued_on"
    t.date "id_expires_on"
    t.string "issuing_authority"
    t.string "bonid"
    t.bigint "address_id"
    t.boolean "welcome_email_sent"
    t.integer "sex"
    t.integer "marital_status"
    t.integer "id_type"
    t.datetime "guidelines_confirmed_at"
    t.integer "role_int"
    t.text "qr_png_base64"
    t.index ["address_id"], name: "index_users_on_address_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "addresses", "communal_sections"
  add_foreign_key "addresses", "partners"
  add_foreign_key "arrondissements", "departments"
  add_foreign_key "communal_sections", "communes"
  add_foreign_key "communes", "arrondissements"
  add_foreign_key "communes", "departments"
  add_foreign_key "identity_submissions", "partners"
  add_foreign_key "identity_submissions", "users"
  add_foreign_key "incident_reports", "addresses"
  add_foreign_key "incident_reports", "officers"
  add_foreign_key "officers", "arrondissements"
  add_foreign_key "officers", "communal_sections"
  add_foreign_key "officers", "communes"
  add_foreign_key "officers", "departments"
  add_foreign_key "officers", "partners"
  add_foreign_key "officers", "users"
  add_foreign_key "partner_applications", "partners"
  add_foreign_key "qr_scan_logs", "partners"
  add_foreign_key "qr_scan_logs", "qr_scans"
  add_foreign_key "qr_scans", "identity_submissions"
  add_foreign_key "qr_scans", "partners"
  add_foreign_key "users", "addresses"
end
