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

ActiveRecord::Schema[8.0].define(version: 2026_04_14_224500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "unaccent"

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
    t.bigint "department_id"
    t.bigint "arrondissement_id"
    t.string "plus_code"
    t.index ["addressable_type", "addressable_id"], name: "index_addresses_on_addressable"
    t.index ["communal_section_id"], name: "index_addresses_on_communal_section_id"
    t.index ["partner_id"], name: "index_addresses_on_partner_id"
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "admin_users_roles", id: false, force: :cascade do |t|
    t.bigint "role_id", null: false
    t.bigint "admin_user_id", null: false
  end

  create_table "api_access_logs", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.bigint "user_id"
    t.string "endpoint"
    t.string "ip_address"
    t.boolean "success"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "duration_ms"
    t.integer "status"
    t.string "response_message"
    t.index ["partner_id"], name: "index_api_access_logs_on_partner_id"
    t.index ["user_id"], name: "index_api_access_logs_on_user_id"
  end

  create_table "api_webhook_events", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.string "event_type"
    t.string "bonid"
    t.jsonb "payload"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "retry_attempts"
    t.string "direction", default: "outbound"
    t.datetime "delivered_at"
    t.string "status", default: "pending"
    t.index ["event_type"], name: "index_api_webhook_events_on_event_type"
    t.index ["partner_id"], name: "index_api_webhook_events_on_partner_id"
    t.index ["status"], name: "index_api_webhook_events_on_status"
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

  create_table "audit_logs", force: :cascade do |t|
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "officer_id"
    t.string "badge_id"
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.text "description"
  end

  create_table "bank_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "bank_id"
    t.string "bank_name"
    t.string "branch_name"
    t.string "account_number"
    t.string "account_type"
    t.string "currency", default: "HTG"
    t.string "wallet_provider"
    t.string "wallet_address"
    t.string "iban"
    t.string "swift_code"
    t.boolean "kyc_verified", default: false, null: false
    t.datetime "kyc_verified_at"
    t.string "kyc_reference_id"
    t.string "status", default: "pending"
    t.string "verification_source"
    t.datetime "last_synced_at"
    t.jsonb "metadata", default: {}
    t.string "created_by_type"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "access_level"
    t.datetime "linked_at", comment: "Timestamp when the user linked this bank/wallet profile"
    t.boolean "currently_open", default: true, null: false, comment: "Indicates whether the account or wallet is still active/open."
    t.date "opened_on", comment: "Date when account or wallet was opened"
    t.date "closed_on", comment: "Date when account or wallet was closed"
    t.string "account_source", default: "bank", null: false
    t.string "chain"
    t.string "cashtag"
    t.index ["account_number"], name: "index_bank_profiles_on_account_number"
    t.index ["account_source"], name: "index_bank_profiles_on_account_source"
    t.index ["bank_id"], name: "index_bank_profiles_on_bank_id"
    t.index ["currently_open"], name: "index_bank_profiles_on_currently_open"
    t.index ["kyc_verified"], name: "index_bank_profiles_on_kyc_verified"
    t.index ["linked_at"], name: "index_bank_profiles_on_linked_at"
    t.index ["metadata"], name: "index_bank_profiles_on_metadata", using: :gin
    t.index ["status"], name: "index_bank_profiles_on_status"
    t.index ["user_id"], name: "index_bank_profiles_on_user_id"
    t.index ["wallet_address"], name: "index_bank_profiles_on_wallet_address"
  end

  create_table "banks", force: :cascade do |t|
    t.string "name", null: false
    t.string "swift_code", null: false
    t.string "slug", null: false
    t.string "country", default: "Haiti", null: false
    t.boolean "verified_partner", default: false, null: false
    t.string "integration_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_banks_on_slug"
    t.index ["swift_code"], name: "index_banks_on_swift_code", unique: true
  end

  create_table "bonid_aliases", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "old_bonid", null: false
    t.string "new_bonid", null: false
    t.string "reason"
    t.datetime "created_at", null: false
    t.index ["new_bonid"], name: "index_bonid_aliases_on_new_bonid"
    t.index ["old_bonid"], name: "index_bonid_aliases_on_old_bonid", unique: true
    t.index ["user_id"], name: "index_bonid_aliases_on_user_id"
  end

  create_table "bonvote_elections", force: :cascade do |t|
    t.string "title", null: false
    t.string "election_type", null: false
    t.integer "round", default: 1, null: false
    t.bigint "parent_election_id"
    t.string "status", default: "draft", null: false
    t.date "election_date", null: false
    t.datetime "opened_at"
    t.datetime "closed_at"
    t.datetime "certified_at"
    t.string "cep_public_key"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["election_type", "round"], name: "index_bonvote_elections_on_election_type_and_round"
    t.index ["parent_election_id"], name: "index_bonvote_elections_on_parent_election_id"
    t.index ["status"], name: "index_bonvote_elections_on_status"
  end

  create_table "border_entries", force: :cascade do |t|
    t.bigint "officer_id", null: false
    t.bigint "visitor_submission_id", null: false
    t.bigint "partner_id"
    t.string "port_of_entry", null: false
    t.integer "entry_mode", default: 0, null: false
    t.string "unit_code"
    t.datetime "entered_at", null: false
    t.datetime "exited_at"
    t.string "transport_reference"
    t.string "transport_provider"
    t.jsonb "metadata", default: {}
    t.string "officer_badge_id"
    t.string "officer_unit_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entered_at"], name: "index_border_entries_on_entered_at"
    t.index ["entry_mode"], name: "index_border_entries_on_entry_mode"
    t.index ["exited_at"], name: "index_border_entries_on_exited_at"
    t.index ["officer_id"], name: "index_border_entries_on_officer_id"
    t.index ["partner_id"], name: "index_border_entries_on_partner_id"
    t.index ["unit_code"], name: "index_border_entries_on_unit_code"
    t.index ["visitor_submission_id"], name: "index_border_entries_on_visitor_submission_id"
  end

  create_table "citizen_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "bonid"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bonid"], name: "index_citizen_profiles_on_bonid"
    t.index ["user_id"], name: "index_citizen_profiles_on_user_id"
  end

  create_table "citizen_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "otp_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "device_fingerprint"
    t.bigint "citizen_profile_id"
    t.string "login_source"
    t.string "ip_address"
    t.string "user_agent"
    t.index ["citizen_profile_id"], name: "index_citizen_sessions_on_citizen_profile_id"
    t.index ["login_source"], name: "index_citizen_sessions_on_login_source"
    t.index ["user_id"], name: "index_citizen_sessions_on_user_id"
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
    t.boolean "launched", default: false, null: false
    t.index ["arrondissement_id"], name: "index_communes_on_arrondissement_id"
    t.index ["department_id"], name: "index_communes_on_department_id"
    t.index ["name"], name: "index_communes_on_name"
  end

  create_table "consent_grants", force: :cascade do |t|
    t.bigint "citizen_id", null: false
    t.bigint "partner_id", null: false
    t.string "scopes", default: [], array: true
    t.datetime "granted_at"
    t.datetime "revoked_at"
    t.datetime "expires_at"
    t.string "grant_token"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "requested_scopes", default: [], array: true
    t.datetime "requested_at"
    t.datetime "deleted_at"
    t.bigint "granted_by_id"
    t.bigint "revoked_by_id"
    t.string "change_reason"
    t.jsonb "audit_log", default: {}
    t.integer "status", default: 0, null: false
    t.text "granted_scopes", default: [], null: false, array: true
    t.datetime "last_accessed_at"
    t.integer "access_count", default: 0, null: false
    t.index ["citizen_id", "partner_id"], name: "index_consent_grants_on_citizen_id_and_partner_id", unique: true
    t.index ["citizen_id"], name: "index_consent_grants_on_citizen_id"
    t.index ["deleted_at"], name: "index_consent_grants_on_deleted_at"
    t.index ["grant_token"], name: "index_consent_grants_on_grant_token", unique: true
    t.index ["last_accessed_at"], name: "index_consent_grants_on_last_accessed_at"
    t.index ["partner_id"], name: "index_consent_grants_on_partner_id"
  end

  create_table "credit_ledger_entries", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.decimal "balance_after", precision: 10, scale: 2, null: false
    t.string "entry_type", null: false
    t.string "description"
    t.string "endpoint_key"
    t.string "payment_method"
    t.string "transaction_id"
    t.string "bonid"
    t.string "ip_address"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint_key"], name: "index_credit_ledger_entries_on_endpoint_key"
    t.index ["entry_type"], name: "index_credit_ledger_entries_on_entry_type"
    t.index ["partner_id", "created_at"], name: "idx_ledger_partner_time"
    t.index ["partner_id"], name: "index_credit_ledger_entries_on_partner_id"
  end

  create_table "crime_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", limit: 10, null: false
    t.text "description"
    t.integer "display_order", default: 0
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_crime_categories_on_active"
    t.index ["code"], name: "index_crime_categories_on_code", unique: true
  end

  create_table "crime_hotspots", force: :cascade do |t|
    t.bigint "commune_id", null: false
    t.bigint "crime_category_id"
    t.date "period_start", null: false
    t.date "period_end", null: false
    t.integer "incident_count", default: 0
    t.float "severity_score", default: 0.0
    t.float "trend_percentage"
    t.jsonb "breakdown", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commune_id", "period_start", "period_end"], name: "idx_hotspots_commune_period"
    t.index ["commune_id"], name: "index_crime_hotspots_on_commune_id"
    t.index ["crime_category_id"], name: "index_crime_hotspots_on_crime_category_id"
    t.index ["severity_score"], name: "index_crime_hotspots_on_severity_score"
  end

  create_table "crime_types", force: :cascade do |t|
    t.bigint "crime_category_id", null: false
    t.string "name", null: false
    t.string "code", limit: 10, null: false
    t.text "description"
    t.text "legal_reference"
    t.integer "base_severity", default: 1
    t.integer "display_order", default: 0
    t.boolean "requires_victim", default: true
    t.boolean "requires_witness", default: false
    t.boolean "requires_location", default: true
    t.boolean "active", default: true
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_crime_types_on_active"
    t.index ["base_severity"], name: "index_crime_types_on_base_severity"
    t.index ["code"], name: "index_crime_types_on_code", unique: true
    t.index ["crime_category_id", "active"], name: "index_crime_types_on_crime_category_id_and_active"
    t.index ["crime_category_id"], name: "index_crime_types_on_crime_category_id"
  end

  create_table "currency_rates", force: :cascade do |t|
    t.string "from_currency", default: "USD", null: false
    t.string "to_currency", default: "HTG", null: false
    t.decimal "rate", precision: 12, scale: 4, null: false
    t.decimal "buffer_percentage", precision: 5, scale: 2, default: "5.0"
    t.decimal "effective_rate", precision: 12, scale: 4
    t.string "source", default: "manual"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["from_currency", "to_currency", "created_at"], name: "idx_currency_rates_lookup"
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

  create_table "dgi_payments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.uuid "verification_record_id"
    t.string "order_id", null: false
    t.decimal "amount_htg", precision: 15, scale: 2, null: false
    t.decimal "fee_htg", precision: 10, scale: 2, default: "0.0"
    t.decimal "total_htg", precision: 15, scale: 2, null: false
    t.string "currency", default: "HTG", null: false
    t.string "payment_method", null: false
    t.string "status", default: "pending", null: false
    t.string "transaction_id"
    t.string "payment_token"
    t.jsonb "provider_response", default: {}
    t.string "form_type"
    t.string "declaration_number"
    t.datetime "paid_at"
    t.string "failure_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["form_type"], name: "index_dgi_payments_on_form_type"
    t.index ["order_id"], name: "index_dgi_payments_on_order_id", unique: true
    t.index ["transaction_id"], name: "index_dgi_payments_on_transaction_id"
    t.index ["user_id", "status"], name: "index_dgi_payments_on_user_id_and_status"
    t.index ["user_id"], name: "index_dgi_payments_on_user_id"
    t.index ["verification_record_id", "status"], name: "index_dgi_payments_on_verification_record_id_and_status"
    t.index ["verification_record_id"], name: "index_dgi_payments_on_verification_record_id"
  end

  create_table "election_accreditations", force: :cascade do |t|
    t.bigint "election_id", null: false
    t.bigint "user_id"
    t.string "accreditation_type", null: false
    t.string "bonid"
    t.string "full_name", null: false
    t.string "cin_number"
    t.string "organization", null: false
    t.string "organization_acronym"
    t.string "photo_url"
    t.string "accreditation_code", null: false
    t.bigint "assigned_body_id"
    t.string "assigned_station_code"
    t.string "department_code"
    t.string "status", default: "pending", null: false
    t.boolean "identity_verified", default: false
    t.string "issued_by"
    t.datetime "issued_at"
    t.datetime "revoked_at"
    t.string "revocation_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_body_id"], name: "index_election_accreditations_on_assigned_body_id"
    t.index ["election_id", "accreditation_code"], name: "idx_accreditations_code", unique: true
    t.index ["election_id", "accreditation_type"], name: "idx_on_election_id_accreditation_type_67ca1597e4"
    t.index ["election_id", "bonid"], name: "idx_accreditations_bonid", unique: true
    t.index ["election_id"], name: "index_election_accreditations_on_election_id"
    t.index ["organization"], name: "index_election_accreditations_on_organization"
    t.index ["user_id"], name: "index_election_accreditations_on_user_id"
  end

  create_table "election_ballots", force: :cascade do |t|
    t.bigint "election_id", null: false
    t.string "nullifier", null: false
    t.string "position", null: false
    t.text "encrypted_choice", null: false
    t.text "encrypted_key"
    t.string "iv"
    t.string "auth_tag"
    t.string "zkp_commitment", null: false
    t.jsonb "zkp_proof", default: {}
    t.string "ballot_hash", null: false
    t.string "receipt_id", null: false
    t.string "channel", default: "remote", null: false
    t.string "consulate_id"
    t.string "station_id"
    t.string "department_code"
    t.string "ip_country"
    t.boolean "location_flagged", default: false
    t.datetime "cast_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ballot_hash"], name: "index_election_ballots_on_ballot_hash", unique: true
    t.index ["cast_at"], name: "index_election_ballots_on_cast_at"
    t.index ["election_id", "channel"], name: "index_election_ballots_on_election_id_and_channel"
    t.index ["election_id", "department_code"], name: "index_election_ballots_on_election_id_and_department_code"
    t.index ["election_id", "nullifier"], name: "idx_ballots_election_nullifier", unique: true
    t.index ["election_id", "position"], name: "index_election_ballots_on_election_id_and_position"
    t.index ["election_id"], name: "index_election_ballots_on_election_id"
    t.index ["receipt_id"], name: "index_election_ballots_on_receipt_id", unique: true
  end

  create_table "election_bodies", force: :cascade do |t|
    t.bigint "election_id", null: false
    t.string "body_type", null: false
    t.string "code", null: false
    t.string "name", null: false
    t.string "department_code"
    t.string "department_name"
    t.integer "commune_id"
    t.integer "arrondissement_id"
    t.bigint "parent_body_id"
    t.string "address"
    t.string "phone"
    t.string "status", default: "active", null: false
    t.integer "registered_voters", default: 0
    t.integer "stations_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commune_id"], name: "index_election_bodies_on_commune_id"
    t.index ["election_id", "body_type"], name: "index_election_bodies_on_election_id_and_body_type"
    t.index ["election_id", "code"], name: "index_election_bodies_on_election_id_and_code", unique: true
    t.index ["election_id", "department_code"], name: "index_election_bodies_on_election_id_and_department_code"
    t.index ["election_id"], name: "index_election_bodies_on_election_id"
    t.index ["parent_body_id"], name: "index_election_bodies_on_parent_body_id"
  end

  create_table "election_candidates", force: :cascade do |t|
    t.bigint "election_id", null: false
    t.bigint "election_constituency_id", null: false
    t.string "position", null: false
    t.string "full_name", null: false
    t.string "party_name"
    t.string "party_acronym"
    t.string "photo_url"
    t.string "department_code"
    t.integer "commune_id"
    t.integer "ballot_number"
    t.integer "votes_round1", default: 0
    t.integer "votes_round2", default: 0
    t.boolean "qualified_runoff", default: false
    t.boolean "winner", default: false
    t.string "status", default: "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "bonid"
    t.string "cin_number"
    t.string "registration_status", default: "draft"
    t.text "platform_statement"
    t.text "rejection_reason"
    t.datetime "submitted_at"
    t.datetime "approved_at"
    t.datetime "rejected_at"
    t.bigint "approved_by_id"
    t.bigint "rejected_by_id"
    t.bigint "party_registration_id"
    t.date "date_of_birth"
    t.string "place_of_birth"
    t.string "nationality", default: "haitian"
    t.string "sex"
    t.string "marital_status"
    t.string "profession"
    t.string "residence_department"
    t.string "residence_commune"
    t.string "residence_address"
    t.integer "residence_years"
    t.string "candidacy_type", default: "party"
    t.text "support_petition_details"
    t.boolean "doc_birth_certificate", default: false
    t.boolean "doc_cin_oni", default: false
    t.boolean "doc_casier_judiciaire", default: false
    t.boolean "doc_dgi_receipt", default: false
    t.boolean "doc_property_proof", default: false
    t.boolean "doc_residence_attestation", default: false
    t.boolean "doc_immigration_cert", default: false
    t.boolean "doc_discharge", default: false
    t.boolean "doc_passport_photos", default: false
    t.boolean "doc_party_mandate", default: false
    t.boolean "doc_support_petition", default: false
    t.boolean "doc_profession_proof", default: false
    t.integer "registration_fee_gourdes"
    t.string "dgi_receipt_number"
    t.boolean "fee_paid", default: false
    t.boolean "fee_reduced", default: false
    t.string "fee_reduction_reason"
    t.string "recepisse_number"
    t.datetime "recepisse_issued_at"
    t.index ["candidacy_type"], name: "index_election_candidates_on_candidacy_type"
    t.index ["election_constituency_id"], name: "index_election_candidates_on_election_constituency_id"
    t.index ["election_id", "bonid"], name: "idx_candidate_election_bonid"
    t.index ["election_id", "department_code"], name: "index_election_candidates_on_election_id_and_department_code"
    t.index ["election_id", "position"], name: "index_election_candidates_on_election_id_and_position"
    t.index ["election_id"], name: "index_election_candidates_on_election_id"
    t.index ["party_registration_id"], name: "index_election_candidates_on_party_registration_id"
    t.index ["recepisse_number"], name: "index_election_candidates_on_recepisse_number", unique: true, where: "(recepisse_number IS NOT NULL)"
    t.index ["registration_status"], name: "index_election_candidates_on_registration_status"
    t.index ["user_id"], name: "index_election_candidates_on_user_id"
  end

  create_table "election_constituencies", force: :cascade do |t|
    t.bigint "election_id", null: false
    t.string "position", null: false
    t.string "department_code"
    t.string "department_name"
    t.integer "commune_id"
    t.integer "arrondissement_id"
    t.string "constituency_name", null: false
    t.integer "seats", default: 1, null: false
    t.boolean "up_for_election", default: true, null: false
    t.string "electoral_system", default: "absolute_majority_two_round", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["election_id", "department_code"], name: "idx_on_election_id_department_code_231ace3839"
    t.index ["election_id", "position"], name: "index_election_constituencies_on_election_id_and_position"
    t.index ["election_id"], name: "index_election_constituencies_on_election_id"
  end

  create_table "election_disputes", force: :cascade do |t|
    t.bigint "election_id", null: false
    t.string "dispute_type", null: false
    t.string "reference_code", null: false
    t.string "filed_by_type", null: false
    t.string "filed_by_name", null: false
    t.string "filed_by_bonid"
    t.string "filed_by_organization"
    t.bigint "constituency_id"
    t.bigint "election_body_id"
    t.string "department_code"
    t.integer "commune_id"
    t.string "subject", null: false
    t.text "description"
    t.text "evidence_summary"
    t.jsonb "attachments", default: []
    t.string "status", default: "filed", null: false
    t.string "priority", default: "normal"
    t.string "assigned_to"
    t.string "assigned_to_bonid"
    t.text "decision"
    t.string "decision_type"
    t.datetime "filed_at"
    t.datetime "hearing_at"
    t.datetime "decided_at"
    t.datetime "appeal_deadline"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["constituency_id"], name: "index_election_disputes_on_constituency_id"
    t.index ["department_code"], name: "index_election_disputes_on_department_code"
    t.index ["election_body_id"], name: "index_election_disputes_on_election_body_id"
    t.index ["election_id", "dispute_type"], name: "index_election_disputes_on_election_id_and_dispute_type"
    t.index ["election_id", "reference_code"], name: "idx_disputes_reference", unique: true
    t.index ["election_id", "status"], name: "index_election_disputes_on_election_id_and_status"
    t.index ["election_id"], name: "index_election_disputes_on_election_id"
  end

  create_table "election_party_registrations", force: :cascade do |t|
    t.bigint "election_id", null: false
    t.bigint "user_id"
    t.string "registration_type", default: "party", null: false
    t.string "party_name", null: false
    t.string "party_acronym"
    t.string "representative_name", null: false
    t.string "representative_bonid"
    t.string "representative_cin"
    t.boolean "is_mandataire", default: false
    t.jsonb "member_parties", default: []
    t.boolean "doc_acte_constitutif", default: false
    t.boolean "doc_acte_reconnaissance", default: false
    t.boolean "doc_statuts", default: false
    t.boolean "doc_pv_assemblee", default: false
    t.boolean "doc_acte_mandataire", default: false
    t.boolean "doc_lettre_ministere", default: false
    t.boolean "doc_sigle", default: false
    t.boolean "doc_embleme", default: false
    t.boolean "doc_cin_representant", default: false
    t.boolean "doc_logo_numerique", default: false
    t.boolean "doc_liste_partis_signataires", default: false
    t.boolean "doc_accord_embleme_unique", default: false
    t.boolean "doc_actes_reconnaissance_membres", default: false
    t.string "status", default: "submitted", null: false
    t.text "rejection_reason"
    t.string "reviewed_by"
    t.datetime "submitted_at"
    t.datetime "reviewed_at"
    t.datetime "approved_at"
    t.datetime "rejected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["election_id", "party_name"], name: "idx_party_reg_name", unique: true
    t.index ["election_id", "status"], name: "idx_party_reg_status"
    t.index ["election_id"], name: "index_election_party_registrations_on_election_id"
    t.index ["registration_type"], name: "index_election_party_registrations_on_registration_type"
    t.index ["user_id"], name: "index_election_party_registrations_on_user_id"
  end

  create_table "election_signatures", force: :cascade do |t|
    t.bigint "election_id", null: false
    t.string "bonid", null: false
    t.string "role", null: false
    t.string "signatory_name", null: false
    t.string "liveness_session_id"
    t.boolean "liveness_verified", default: false
    t.string "key_shard_hash"
    t.datetime "signed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["election_id", "bonid"], name: "index_election_signatures_on_election_id_and_bonid", unique: true
    t.index ["election_id", "role"], name: "index_election_signatures_on_election_id_and_role", unique: true
    t.index ["election_id"], name: "index_election_signatures_on_election_id"
  end

  create_table "election_staff_assignments", force: :cascade do |t|
    t.bigint "election_id", null: false
    t.bigint "user_id", null: false
    t.bigint "election_body_id", null: false
    t.string "role", null: false
    t.string "bonid"
    t.string "status", default: "assigned", null: false
    t.boolean "identity_verified", default: false
    t.datetime "assigned_at"
    t.datetime "checked_in_at"
    t.datetime "checked_out_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["election_body_id", "role"], name: "index_election_staff_assignments_on_election_body_id_and_role"
    t.index ["election_body_id"], name: "index_election_staff_assignments_on_election_body_id"
    t.index ["election_id", "role"], name: "index_election_staff_assignments_on_election_id_and_role"
    t.index ["election_id", "user_id", "election_body_id"], name: "idx_staff_election_body", unique: true
    t.index ["election_id"], name: "index_election_staff_assignments_on_election_id"
    t.index ["user_id"], name: "index_election_staff_assignments_on_user_id"
  end

  create_table "electoral_calendars", force: :cascade do |t|
    t.bigint "bonvote_election_id", null: false
    t.string "phase", null: false
    t.string "name", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.text "description"
    t.string "responsible_body"
    t.boolean "public_visible", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bonvote_election_id", "phase"], name: "index_electoral_calendars_on_bonvote_election_id_and_phase"
    t.index ["bonvote_election_id"], name: "index_electoral_calendars_on_bonvote_election_id"
    t.index ["phase"], name: "index_electoral_calendars_on_phase"
    t.index ["start_date", "end_date"], name: "index_electoral_calendars_on_start_date_and_end_date"
  end

  create_table "emergency_contacts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.string "phone"
    t.string "email"
    t.string "relation"
    t.string "address"
    t.string "bonid"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "visibility", default: 0, null: false
    t.integer "verification_status", default: 0, null: false
    t.index ["user_id"], name: "index_emergency_contacts_on_user_id"
  end

  create_table "failed_bonid_lookups", force: :cascade do |t|
    t.string "bonid"
    t.string "verification_token"
    t.string "signature"
    t.bigint "officer_id"
    t.string "reason"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["officer_id"], name: "index_failed_bonid_lookups_on_officer_id"
  end

  create_table "family_members", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "relationship", default: 0, null: false
    t.string "first_name", null: false
    t.string "middle_name"
    t.string "last_name", null: false
    t.date "date_of_birth"
    t.string "place_of_birth"
    t.string "nationality", default: "Haitian"
    t.boolean "alive", default: true, null: false
    t.bigint "linked_user_id"
    t.string "linked_bonid"
    t.datetime "link_confirmed_at"
    t.string "link_consent_token"
    t.datetime "link_consent_sent_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "date_of_death"
    t.string "guardian_type"
    t.bigint "birth_department_id"
    t.bigint "birth_commune_id"
    t.integer "verification_status", default: 0, null: false
    t.index ["birth_commune_id"], name: "index_family_members_on_birth_commune_id"
    t.index ["birth_department_id"], name: "index_family_members_on_birth_department_id"
    t.index ["link_consent_token"], name: "idx_family_link_consent_token", unique: true, where: "(link_consent_token IS NOT NULL)"
    t.index ["linked_user_id"], name: "idx_family_linked_user", where: "(linked_user_id IS NOT NULL)"
    t.index ["user_id", "relationship"], name: "idx_family_one_mother_one_father", unique: true, where: "(relationship = ANY (ARRAY[0, 1]))"
    t.index ["user_id"], name: "index_family_members_on_user_id"
  end

  create_table "health_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "blood_type"
    t.text "allergies", default: [], array: true
    t.text "chronic_conditions", default: [], array: true
    t.text "medications", default: [], array: true
    t.boolean "organ_donor", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "allergies_other"
    t.string "chronic_conditions_other"
    t.string "medications_other"
    t.index ["user_id"], name: "index_health_profiles_on_user_id"
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
    t.string "id_type"
    t.integer "staged_for", default: 0, null: false
    t.bigint "partner_id", null: false
    t.string "bonid"
    t.string "hmac_signature"
    t.text "public_qr_png_base64"
    t.text "secure_qr_png_base64"
    t.integer "qr_scan_logs_count", default: 0, null: false
    t.string "document_issuer"
    t.jsonb "signature_metadata", default: {}, null: false
    t.string "signature_hash"
    t.datetime "signature_verified_at"
    t.bigint "signature_verifier_id"
    t.string "signature_verification_method"
    t.text "signature_verification_note"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "invalidated_at"
    t.jsonb "metadata", default: {}, null: false
    t.integer "submission_type", default: 0
    t.string "public_token"
    t.integer "reviewer_id"
    t.integer "reviewed_by_admin_id"
    t.string "hmac_signature_value"
    t.string "ninu", limit: 10
    t.string "document_number"
    t.date "document_expiry_date"
    t.date "document_issue_date"
    t.string "country_of_residence", default: "HT"
    t.string "host_country_id_type"
    t.string "diaspora_proof_type"
    t.index ["created_at"], name: "index_identity_submissions_on_created_at"
    t.index ["document_number"], name: "index_identity_submissions_on_document_number"
    t.index ["ninu"], name: "index_identity_submissions_on_ninu"
    t.index ["partner_id"], name: "index_identity_submissions_on_partner_id"
    t.index ["public_token"], name: "index_identity_submissions_on_public_token", unique: true
    t.index ["signature_hash"], name: "index_identity_submissions_on_signature_hash"
    t.index ["signature_verified_at"], name: "index_identity_submissions_on_signature_verified_at"
    t.index ["signature_verifier_id"], name: "index_identity_submissions_on_signature_verifier_id"
    t.index ["status"], name: "index_identity_submissions_on_status"
    t.index ["user_id", "status", "created_at"], name: "idx_submissions_user_status_recent"
    t.index ["user_id", "status"], name: "idx_identity_submissions_user_status"
    t.index ["user_id"], name: "index_identity_submissions_on_user_id"
  end

  create_table "incident_links", force: :cascade do |t|
    t.bigint "incident_report_id", null: false
    t.bigint "linked_incident_id", null: false
    t.string "link_type", null: false
    t.text "notes"
    t.string "created_by_type"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_type", "created_by_id"], name: "index_incident_links_on_created_by"
    t.index ["incident_report_id", "linked_incident_id"], name: "idx_incident_links_unique", unique: true
    t.index ["incident_report_id"], name: "index_incident_links_on_incident_report_id"
    t.index ["link_type"], name: "index_incident_links_on_link_type"
    t.index ["linked_incident_id"], name: "index_incident_links_on_linked_incident_id"
  end

  create_table "incident_reports", force: :cascade do |t|
    t.bigint "officer_id", null: false
    t.string "crime_type"
    t.text "description"
    t.datetime "occurred_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "report_status"
    t.text "review_comment"
    t.integer "reviewed_by_id"
    t.string "report_id"
    t.string "officer_name"
    t.string "officer_bonid"
    t.string "officer_unit"
    t.datetime "submitted_at"
    t.string "bonid_case_number"
    t.string "qr_code"
    t.string "status"
    t.bigint "partner_id"
    t.bigint "crime_type_record_id"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "report_signature"
    t.datetime "report_signed_at"
    t.string "signed_by_badge_id"
    t.datetime "officer_attested_at"
    t.index ["bonid_case_number"], name: "index_incident_reports_on_bonid_case_number"
    t.index ["crime_type"], name: "index_incident_reports_on_crime_type"
    t.index ["crime_type_record_id"], name: "index_incident_reports_on_crime_type_record_id"
    t.index ["occurred_at"], name: "index_incident_reports_on_occurred_at"
    t.index ["officer_bonid"], name: "index_incident_reports_on_officer_bonid"
    t.index ["officer_id", "status", "created_at"], name: "idx_incidents_officer_status_date"
    t.index ["officer_id"], name: "index_incident_reports_on_officer_id"
    t.index ["partner_id", "status"], name: "idx_incidents_partner_status"
    t.index ["partner_id"], name: "index_incident_reports_on_partner_id"
    t.index ["report_id"], name: "index_incident_reports_on_report_id", unique: true
    t.index ["status"], name: "index_incident_reports_on_status"
    t.index ["submitted_at"], name: "index_incident_reports_on_submitted_at"
    t.index ["uuid"], name: "index_incident_reports_on_uuid", unique: true
  end

  create_table "incident_reviews", force: :cascade do |t|
    t.bigint "incident_report_id", null: false
    t.bigint "reviewer_id", null: false
    t.bigint "assigned_by_id"
    t.integer "decision"
    t.text "summary"
    t.datetime "assigned_at"
    t.datetime "deadline_at"
    t.datetime "completed_at"
    t.integer "priority", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_by_id"], name: "index_incident_reviews_on_assigned_by_id"
    t.index ["incident_report_id", "created_at"], name: "index_incident_reviews_on_incident_report_id_and_created_at"
    t.index ["incident_report_id"], name: "index_incident_reviews_on_incident_report_id"
    t.index ["priority"], name: "index_incident_reviews_on_priority"
    t.index ["reviewer_id", "decision"], name: "index_incident_reviews_on_reviewer_id_and_decision"
    t.index ["reviewer_id"], name: "index_incident_reviews_on_reviewer_id"
  end

  create_table "invite_codes", force: :cascade do |t|
    t.string "code", null: false
    t.string "code_type", default: "personal"
    t.integer "max_uses", default: 1
    t.integer "uses_count", default: 0
    t.bigint "partner_id"
    t.bigint "commune_id"
    t.bigint "user_id"
    t.datetime "expires_at"
    t.boolean "active", default: true, null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_invite_codes_on_code", unique: true
    t.index ["code_type"], name: "index_invite_codes_on_code_type"
    t.index ["commune_id"], name: "index_invite_codes_on_commune_id"
    t.index ["partner_id"], name: "index_invite_codes_on_partner_id"
    t.index ["user_id"], name: "index_invite_codes_on_user_id"
  end

  create_table "local_contacts", force: :cascade do |t|
    t.string "name", null: false
    t.string "phone"
    t.string "email"
    t.string "relationship"
    t.boolean "verified", default: false, null: false
    t.string "bonid"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "visitor_submission_id"
    t.string "phone_country_code"
    t.index ["bonid"], name: "index_local_contacts_on_bonid"
    t.index ["user_id"], name: "index_local_contacts_on_user_id"
    t.index ["visitor_submission_id"], name: "index_local_contacts_on_visitor_submission_id"
  end

  create_table "name_change_requests", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "reviewed_by_id"
    t.string "old_first_name", null: false
    t.string "old_middle_name"
    t.string "old_last_name", null: false
    t.string "new_first_name", null: false
    t.string "new_middle_name"
    t.string "new_last_name", null: false
    t.integer "status", default: 0, null: false
    t.string "reason", null: false
    t.text "other_reason"
    t.text "rejection_reason"
    t.text "admin_note"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reviewed_by_id"], name: "index_name_change_requests_on_reviewed_by_id"
    t.index ["status"], name: "index_name_change_requests_on_status"
    t.index ["user_id"], name: "index_name_change_requests_on_user_id"
  end

  create_table "o_auth_access_tokens", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.bigint "citizen_id", null: false
    t.string "token", null: false
    t.string "scopes", default: [], array: true
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "refresh_token"
    t.index ["citizen_id"], name: "index_o_auth_access_tokens_on_citizen_id"
    t.index ["expires_at"], name: "index_o_auth_access_tokens_on_expires_at"
    t.index ["partner_id"], name: "index_o_auth_access_tokens_on_partner_id"
    t.index ["refresh_token"], name: "index_o_auth_access_tokens_on_refresh_token", unique: true
    t.index ["token"], name: "index_o_auth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.string "name"
    t.string "uid"
    t.string "secret_digest"
    t.text "redirect_uri"
    t.string "scopes"
    t.bigint "partner_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["partner_id"], name: "index_oauth_applications_on_partner_id"
  end

  create_table "oauth_authorization_codes", force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "expires_at"
    t.datetime "used_at"
    t.bigint "oauth_application_id", null: false
    t.bigint "user_id", null: false
    t.text "redirect_uri"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_digest"], name: "index_oauth_authorization_codes_on_code_digest", unique: true
    t.index ["oauth_application_id"], name: "index_oauth_authorization_codes_on_oauth_application_id"
    t.index ["user_id"], name: "index_oauth_authorization_codes_on_user_id"
  end

  create_table "oauth_events", force: :cascade do |t|
    t.bigint "oauth_application_id", null: false
    t.bigint "user_id"
    t.string "event_type", null: false
    t.string "status", default: "pending"
    t.jsonb "payload"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_oauth_events_on_event_type"
    t.index ["oauth_application_id"], name: "index_oauth_events_on_oauth_application_id"
    t.index ["status"], name: "index_oauth_events_on_status"
    t.index ["user_id"], name: "index_oauth_events_on_user_id"
  end

  create_table "officer_complaints", force: :cascade do |t|
    t.string "tracking_number", null: false
    t.string "status", default: "submitted", null: false
    t.string "uuid", null: false
    t.string "complainant_type", default: "citizen", null: false
    t.string "complainant_role", null: false
    t.string "complainant_name"
    t.string "complainant_bonid"
    t.string "complainant_cin"
    t.string "complainant_phone"
    t.string "complainant_email"
    t.string "complainant_nationality"
    t.bigint "user_id"
    t.bigint "visitor_submission_id"
    t.datetime "occurred_at", null: false
    t.text "location_description"
    t.string "pnh_unit_involved"
    t.string "routed_directorate"
    t.bigint "department_id"
    t.bigint "commune_id"
    t.bigint "communal_section_id"
    t.bigint "accused_officer_id"
    t.string "accused_officer_badge"
    t.string "accused_officer_name"
    t.string "accused_officer_vehicle"
    t.string "accused_officer_unit"
    t.text "physical_description"
    t.string "allegation_category", null: false
    t.string "specific_allegation", null: false
    t.text "narrative", null: false
    t.jsonb "witnesses", default: [], null: false
    t.bigint "assigned_to_id"
    t.bigint "assigned_by_id"
    t.text "internal_notes"
    t.text "resolution_notes"
    t.datetime "submitted_at"
    t.datetime "reviewed_at"
    t.datetime "investigation_opened_at"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "certificate_signature"
    t.datetime "certificate_signed_at"
    t.bigint "arrondissement_id"
    t.string "street_address"
    t.string "locality"
    t.string "postal_code"
    t.string "country", default: "Haiti"
    t.index ["accused_officer_id"], name: "index_officer_complaints_on_accused_officer_id"
    t.index ["allegation_category"], name: "index_officer_complaints_on_allegation_category"
    t.index ["arrondissement_id"], name: "index_officer_complaints_on_arrondissement_id"
    t.index ["assigned_to_id"], name: "index_officer_complaints_on_assigned_to_id"
    t.index ["communal_section_id"], name: "index_officer_complaints_on_communal_section_id"
    t.index ["commune_id"], name: "index_officer_complaints_on_commune_id"
    t.index ["complainant_bonid"], name: "index_officer_complaints_on_complainant_bonid"
    t.index ["complainant_type"], name: "index_officer_complaints_on_complainant_type"
    t.index ["department_id"], name: "index_officer_complaints_on_department_id"
    t.index ["occurred_at"], name: "index_officer_complaints_on_occurred_at"
    t.index ["routed_directorate"], name: "index_officer_complaints_on_routed_directorate"
    t.index ["status"], name: "index_officer_complaints_on_status"
    t.index ["tracking_number"], name: "index_officer_complaints_on_tracking_number", unique: true
    t.index ["user_id"], name: "index_officer_complaints_on_user_id"
    t.index ["uuid"], name: "index_officer_complaints_on_uuid", unique: true
    t.index ["visitor_submission_id"], name: "index_officer_complaints_on_visitor_submission_id"
  end

  create_table "officer_metrics", force: :cascade do |t|
    t.bigint "officer_id", null: false
    t.date "period_start", null: false
    t.date "period_end", null: false
    t.integer "reports_submitted", default: 0
    t.integer "reports_approved", default: 0
    t.integer "reports_rejected", default: 0
    t.float "approval_rate", default: 0.0
    t.float "avg_review_time_hours"
    t.integer "bonid_scans", default: 0
    t.jsonb "crime_type_breakdown", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["officer_id", "period_start"], name: "index_officer_metrics_on_officer_id_and_period_start", unique: true
    t.index ["officer_id"], name: "index_officer_metrics_on_officer_id"
  end

  create_table "officers", force: :cascade do |t|
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
    t.string "first_name"
    t.string "middle_name"
    t.string "last_name"
    t.datetime "password_confirmed_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.inet "current_sign_in_ip"
    t.inet "last_sign_in_ip"
    t.boolean "approved", default: false, null: false
    t.datetime "invitation_created_at"
    t.datetime "invitation_sent_at"
    t.integer "invitation_limit"
    t.bigint "invited_by_id"
    t.string "invited_by_type"
    t.integer "invitations_count", default: 0
    t.string "department_directorate"
    t.index ["arrondissement_id"], name: "index_officers_on_arrondissement_id"
    t.index ["badge_id"], name: "index_officers_on_badge_id", unique: true
    t.index ["communal_section_id"], name: "index_officers_on_communal_section_id"
    t.index ["commune_id"], name: "index_officers_on_commune_id"
    t.index ["department_id"], name: "index_officers_on_department_id"
    t.index ["email"], name: "index_officers_on_email", unique: true
    t.index ["invitation_token"], name: "index_officers_on_invitation_token", unique: true
    t.index ["invited_by_id", "invited_by_type"], name: "index_officers_on_invited_by_id_and_invited_by_type"
    t.index ["partner_id"], name: "index_officers_on_partner_id"
    t.index ["reset_password_token"], name: "index_officers_on_reset_password_token"
    t.index ["user_id"], name: "index_officers_on_user_id"
  end

  create_table "partner_access_logs", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.bigint "admin_user_id"
    t.string "action", null: false
    t.string "reason"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_partner_access_logs_on_action"
    t.index ["admin_user_id"], name: "index_partner_access_logs_on_admin_user_id"
    t.index ["created_at"], name: "index_partner_access_logs_on_created_at"
    t.index ["partner_id"], name: "index_partner_access_logs_on_partner_id"
  end

  create_table "partner_api_logs", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.string "endpoint"
    t.string "request_method"
    t.integer "status_code"
    t.integer "status"
    t.float "response_time_ms"
    t.string "ip_address"
    t.text "user_agent"
    t.text "request_payload"
    t.text "response_body"
    t.datetime "requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "log_status"
    t.index ["partner_id"], name: "index_partner_api_logs_on_partner_id"
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
    t.string "contact_code"
    t.string "use_cases", default: [], array: true
    t.string "rejection_reason"
    t.bigint "partner_id"
    t.text "description"
    t.string "unit_name"
    t.string "unit_type"
    t.string "partner_admin_email"
    t.text "rejection_comment"
    t.integer "status", default: 0, null: false
    t.boolean "approved", default: false, null: false
    t.integer "partner_plan_id"
    t.index ["partner_id"], name: "index_partner_applications_on_partner_id"
  end

  create_table "partner_audit_logs", force: :cascade do |t|
    t.bigint "partner_id"
    t.bigint "admin_user_id"
    t.string "event", null: false
    t.text "details"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_partner_audit_logs_on_admin_user_id"
    t.index ["created_at"], name: "index_partner_audit_logs_on_created_at"
    t.index ["partner_id"], name: "index_partner_audit_logs_on_partner_id"
  end

  create_table "partner_branches", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.string "name", null: false
    t.string "code"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_partner_branches_on_code"
    t.index ["partner_id"], name: "index_partner_branches_on_partner_id"
  end

  create_table "partner_payments", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.bigint "partner_plan_id"
    t.string "payment_method", null: false, comment: "moncash or stripe"
    t.string "order_id", null: false, comment: "Our generated unique order ID"
    t.string "transaction_id", comment: "MonCash transaction ID or Stripe payment intent"
    t.string "payment_token", comment: "MonCash redirect token"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "HTG", null: false
    t.string "status", default: "pending", null: false, comment: "pending, completed, failed, refunded"
    t.string "payment_type", default: "subscription", null: false, comment: "subscription, addon, overage"
    t.datetime "paid_at"
    t.datetime "billing_period_start"
    t.datetime "billing_period_end"
    t.jsonb "metadata", default: {}
    t.text "failure_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "reconciled_at"
    t.string "reconciled_by"
    t.integer "reconciliation_attempts", default: 0
    t.string "last_reconciliation_error"
    t.decimal "credits", precision: 10, scale: 2
    t.index ["order_id"], name: "index_partner_payments_on_order_id", unique: true
    t.index ["partner_id", "status"], name: "index_partner_payments_on_partner_id_and_status"
    t.index ["partner_id"], name: "index_partner_payments_on_partner_id"
    t.index ["partner_plan_id"], name: "index_partner_payments_on_partner_plan_id"
    t.index ["payment_type"], name: "index_partner_payments_on_payment_type"
    t.index ["status"], name: "index_partner_payments_on_status"
    t.index ["transaction_id"], name: "index_partner_payments_on_transaction_id"
  end

  create_table "partner_plans", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.text "description"
    t.decimal "price"
    t.string "billing_cycle"
    t.integer "max_verifications"
    t.integer "max_admins"
    t.boolean "api_access"
    t.boolean "custom_domain"
    t.boolean "priority_support"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "price_per_extra_verif"
    t.decimal "price_per_extra_admin"
    t.string "stripe_price_id"
    t.string "stripe_product_id"
    t.string "target_audience"
    t.jsonb "metadata", default: {}
    t.decimal "price_htg", precision: 10, scale: 2, default: "0.0"
    t.decimal "price_per_extra_verif_htg", precision: 10, scale: 2, default: "0.0"
    t.decimal "price_per_extra_admin_htg", precision: 10, scale: 2, default: "0.0"
    t.integer "rate_limit", default: 20, comment: "API requests per minute (or per day for free)"
    t.index ["slug"], name: "index_partner_plans_on_slug", unique: true
    t.index ["stripe_price_id"], name: "index_partner_plans_on_stripe_price_id"
  end

  create_table "partner_schemas", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.string "name"
    t.string "record_type"
    t.jsonb "structure"
    t.jsonb "validation_rules"
    t.string "visibility"
    t.integer "version"
    t.boolean "active"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "approved_by_id"
    t.boolean "template", default: false
    t.string "sector"
    t.text "description"
    t.string "pricing_type", default: "free"
    t.integer "price_cents", default: 0
    t.string "currency", default: "HTG"
    t.string "service_icon", default: "ri-file-text-line"
    t.string "service_category", default: "verification"
    t.integer "position", default: 0
    t.boolean "citizen_facing", default: false
    t.boolean "requires_signature", default: false
    t.boolean "auto_stamp", default: false
    t.jsonb "draft_structure"
    t.datetime "published_at"
    t.string "schema_status", default: "draft"
    t.string "form_code"
    t.string "form_revision"
    t.integer "capacity"
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.index ["approved_by_id"], name: "index_partner_schemas_on_approved_by_id"
    t.index ["citizen_facing", "active"], name: "index_partner_schemas_on_citizen_facing_and_active"
    t.index ["form_code"], name: "index_partner_schemas_on_form_code"
    t.index ["partner_id", "citizen_facing"], name: "index_partner_schemas_on_partner_id_and_citizen_facing"
    t.index ["partner_id", "record_type", "schema_status"], name: "idx_schemas_partner_record_status"
    t.index ["partner_id"], name: "index_partner_schemas_on_partner_id"
    t.index ["sector"], name: "index_partner_schemas_on_sector"
    t.index ["template"], name: "index_partner_schemas_on_template"
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
    t.integer "admin_user_id"
    t.string "type"
    t.integer "qr_scans_count", default: 0, null: false
    t.string "api_key_digest"
    t.boolean "active"
    t.datetime "api_key_rotated_at"
    t.string "estimated_team_size"
    t.integer "intended_users_to_verify"
    t.string "preferred_integration"
    t.string "how_did_you_hear"
    t.bigint "partner_plan_id"
    t.integer "status", default: 0, null: false
    t.string "unit_type"
    t.string "unit_name"
    t.string "department_sector"
    t.string "other_use_case"
    t.string "email_verification_token"
    t.datetime "email_verified_at"
    t.text "rejection_reason"
    t.text "rejection_comment"
    t.datetime "deleted_at"
    t.integer "deleted_by_admin_id"
    t.text "deleted_reason"
    t.datetime "suspended_at"
    t.integer "suspended_by_admin_id"
    t.text "suspended_reason"
    t.jsonb "redirect_uris", default: [], null: false
    t.string "default_redirect_uri"
    t.jsonb "allowed_scopes", default: [], null: false
    t.string "payment_method", default: "none"
    t.datetime "billing_period_start"
    t.datetime "billing_period_end"
    t.string "plan_status", default: "inactive"
    t.string "moncash_customer_id"
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.datetime "last_payment_at"
    t.datetime "grace_period_ends_at"
    t.integer "monthly_verifications_used", default: 0
    t.datetime "verifications_reset_at"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "webhook_url"
    t.string "webhook_secret"
    t.boolean "critical_incident_active", default: false, null: false
    t.string "critical_incident_message"
    t.datetime "critical_incident_activated_at"
    t.jsonb "allowed_transaction_types", default: [], null: false
    t.decimal "credit_balance", precision: 10, scale: 2, default: "0.0", null: false
    t.string "settlement_cashtag"
    t.string "settlement_method"
    t.jsonb "settlement_bank_details"
    t.datetime "guidelines_accepted_at"
    t.string "guidelines_version"
    t.bigint "guidelines_accepted_by_id"
    t.index ["allowed_scopes"], name: "index_partners_on_allowed_scopes", using: :gin
    t.index ["allowed_transaction_types"], name: "index_partners_on_allowed_transaction_types", using: :gin
    t.index ["api_key_digest"], name: "index_partners_on_api_key_digest"
    t.index ["billing_period_end"], name: "index_partners_on_billing_period_end"
    t.index ["deleted_at"], name: "index_partners_on_deleted_at"
    t.index ["guidelines_accepted_at"], name: "index_partners_on_guidelines_accepted_at"
    t.index ["moncash_customer_id"], name: "index_partners_on_moncash_customer_id"
    t.index ["partner_plan_id"], name: "index_partners_on_partner_plan_id"
    t.index ["payment_method"], name: "index_partners_on_payment_method"
    t.index ["plan_status"], name: "index_partners_on_plan_status"
    t.index ["redirect_uris"], name: "index_partners_on_redirect_uris", using: :gin
    t.index ["stripe_customer_id"], name: "index_partners_on_stripe_customer_id"
    t.index ["suspended_at"], name: "index_partners_on_suspended_at"
    t.index ["unit_type"], name: "index_partners_on_unit_type"
    t.index ["uuid"], name: "index_partners_on_uuid", unique: true
  end

  create_table "permissions", force: :cascade do |t|
    t.string "action", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_permissions_on_action", unique: true
  end

  create_table "permissions_roles", id: false, force: :cascade do |t|
    t.bigint "permission_id", null: false
    t.bigint "role_id", null: false
    t.index ["permission_id", "role_id"], name: "index_permissions_roles_on_permission_id_and_role_id", unique: true
    t.index ["permission_id"], name: "index_permissions_roles_on_permission_id"
    t.index ["role_id"], name: "index_permissions_roles_on_role_id"
  end

  create_table "person_involvements", force: :cascade do |t|
    t.bigint "incident_report_id", null: false
    t.bigint "user_id"
    t.bigint "address_id"
    t.string "bonid"
    t.string "name"
    t.integer "role", default: 4, null: false
    t.boolean "no_bonid", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status"
    t.string "cin"
    t.string "cin_unique_id"
    t.string "phone"
    t.string "email"
    t.string "address"
    t.string "first_name"
    t.string "middle_name"
    t.string "last_name"
    t.string "sex"
    t.date "date_of_birth"
    t.string "nationality"
    t.date "id_issued_on"
    t.date "id_expires_on"
    t.integer "place_of_birth_department_id"
    t.integer "place_of_birth_commune_id"
    t.string "passport_number"
    t.string "issuing_authority"
    t.string "id_type"
    t.boolean "notify_emergency_contact", default: false, null: false
    t.bigint "visitor_submission_id"
    t.index ["address_id"], name: "index_person_involvements_on_address_id"
    t.index ["bonid"], name: "index_person_involvements_on_bonid"
    t.index ["incident_report_id", "role"], name: "idx_pi_report_role"
    t.index ["incident_report_id"], name: "index_person_involvements_on_incident_report_id"
    t.index ["role"], name: "index_person_involvements_on_role"
    t.index ["user_id"], name: "index_person_involvements_on_user_id"
    t.index ["visitor_submission_id"], name: "index_person_involvements_on_visitor_submission_id"
  end

  create_table "physical_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.float "weight_kg"
    t.float "height_cm"
    t.string "race"
    t.string "eye_color"
    t.string "hair_color"
    t.string "body_type"
    t.string "skin_tone"
    t.string "facial_hair"
    t.string "handedness"
    t.boolean "tattoos", default: false
    t.text "scars"
    t.text "birthmarks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "hair_style"
    t.index ["user_id"], name: "index_physical_profiles_on_user_id"
  end

  create_table "pilot_feedbacks", force: :cascade do |t|
    t.string "election_id", null: false
    t.string "receipt_id"
    t.string "ballot_hash"
    t.integer "time_to_vote", null: false
    t.integer "photo_clarity", null: false
    t.integer "trust_level", null: false
    t.text "comment"
    t.string "lang", default: "ht"
    t.string "channel"
    t.string "consulate_id"
    t.string "ip_country"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["election_id"], name: "index_pilot_feedbacks_on_election_id"
    t.index ["receipt_id"], name: "index_pilot_feedbacks_on_receipt_id", unique: true
    t.index ["trust_level"], name: "index_pilot_feedbacks_on_trust_level"
  end

  create_table "plan_add_ons", force: :cascade do |t|
    t.string "name", null: false
    t.integer "price_cents", default: 0, null: false
    t.string "unit"
    t.bigint "partner_plan_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["partner_plan_id"], name: "index_plan_add_ons_on_partner_plan_id"
  end

  create_table "plan_features", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "included", default: false, null: false
    t.bigint "partner_plan_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["partner_plan_id"], name: "index_plan_features_on_partner_plan_id"
  end

  create_table "qr_scan_logs", force: :cascade do |t|
    t.bigint "qr_scan_id", null: false
    t.bigint "partner_id"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "identity_submission_id", null: false
    t.bigint "officer_id"
    t.datetime "scanned_at"
    t.string "source"
    t.string "country"
    t.string "city"
    t.string "region"
    t.string "organization"
    t.index ["identity_submission_id"], name: "index_qr_scan_logs_on_identity_submission_id"
    t.index ["officer_id"], name: "index_qr_scan_logs_on_officer_id"
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
    t.bigint "partner_id"
    t.bigint "officer_id"
    t.string "partner_slug"
    t.boolean "manual"
    t.string "scan_method"
    t.integer "partner_branch_id"
    t.integer "department_id"
    t.jsonb "metadata"
    t.float "latitude"
    t.float "longitude"
    t.integer "status"
    t.bigint "banking_agent_id"
    t.index ["banking_agent_id"], name: "index_qr_scans_on_banking_agent_id"
    t.index ["identity_submission_id"], name: "index_qr_scans_on_identity_submission_id"
    t.index ["latitude", "longitude"], name: "index_qr_scans_on_latitude_and_longitude"
    t.index ["officer_id"], name: "index_qr_scans_on_officer_id"
    t.index ["partner_id"], name: "index_qr_scans_on_partner_id"
  end

  create_table "related_crime_types", force: :cascade do |t|
    t.bigint "crime_type_id", null: false
    t.bigint "related_crime_type_id", null: false
    t.string "relationship_type"
    t.float "correlation_score", default: 0.5
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["crime_type_id", "related_crime_type_id"], name: "idx_related_crimes_unique", unique: true
    t.index ["crime_type_id"], name: "index_related_crime_types_on_crime_type_id"
    t.index ["related_crime_type_id"], name: "index_related_crime_types_on_related_crime_type_id"
  end

  create_table "review_comments", force: :cascade do |t|
    t.bigint "incident_review_id", null: false
    t.bigint "person_involvement_id"
    t.bigint "admin_user_id", null: false
    t.text "content", null: false
    t.string "comment_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_review_comments_on_admin_user_id"
    t.index ["incident_review_id"], name: "index_review_comments_on_incident_review_id"
    t.index ["person_involvement_id"], name: "index_review_comments_on_person_involvement_id"
  end

  create_table "reviewer_activities", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "action", null: false
    t.string "target_type"
    t.bigint "target_id"
    t.jsonb "metadata", default: {}
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_reviewer_activities_on_action"
    t.index ["created_at"], name: "index_reviewer_activities_on_created_at"
    t.index ["target_type", "target_id"], name: "index_reviewer_activities_on_target_type_and_target_id"
    t.index ["user_id"], name: "index_reviewer_activities_on_user_id"
  end

  create_table "reviewers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "roles", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "resource_type"
    t.integer "resource_id"
    t.string "slug"
    t.index ["name"], name: "index_roles_on_name"
    t.index ["resource_id"], name: "index_roles_on_resource_id"
    t.index ["resource_type"], name: "index_roles_on_resource_type"
    t.index ["slug"], name: "index_roles_on_slug"
  end

  create_table "roles_users", id: false, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "role_id", null: false
    t.index ["role_id", "user_id"], name: "index_roles_users_on_role_id_and_user_id"
    t.index ["user_id", "role_id"], name: "index_roles_users_on_user_id_and_role_id", unique: true
  end

  create_table "service_applications", force: :cascade do |t|
    t.bigint "citizen_id", null: false
    t.bigint "partner_id", null: false
    t.bigint "partner_schema_id", null: false
    t.integer "schema_version", null: false
    t.jsonb "schema_snapshot", default: {}, null: false
    t.jsonb "form_data", default: {}, null: false
    t.jsonb "calculated_values", default: {}
    t.boolean "signature_consented", default: false
    t.datetime "signature_applied_at"
    t.boolean "sealed", default: false
    t.datetime "sealed_at"
    t.string "seal_checksum"
    t.string "status", default: "draft", null: false
    t.text "rejection_reason"
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.datetime "submitted_at"
    t.string "pdf_checksum"
    t.datetime "pdf_generated_at"
    t.integer "total_price_cents", default: 0
    t.string "currency", default: "HTG"
    t.boolean "paid", default: false
    t.datetime "paid_at"
    t.string "verification_code", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "price_snapshot", default: {}
    t.jsonb "staff_notes", default: []
    t.string "payment_method"
    t.string "payment_token"
    t.string "payment_transaction_id"
    t.datetime "checked_in_at"
    t.index ["citizen_id", "status"], name: "index_service_applications_on_citizen_id_and_status"
    t.index ["citizen_id"], name: "index_service_applications_on_citizen_id"
    t.index ["partner_id", "status"], name: "index_service_applications_on_partner_id_and_status"
    t.index ["partner_id"], name: "index_service_applications_on_partner_id"
    t.index ["partner_schema_id", "schema_version"], name: "idx_svc_app_schema_version"
    t.index ["partner_schema_id"], name: "index_service_applications_on_partner_schema_id"
    t.index ["payment_token"], name: "index_service_applications_on_payment_token", unique: true, where: "(payment_token IS NOT NULL)"
    t.index ["reviewed_by_id"], name: "index_service_applications_on_reviewed_by_id"
    t.index ["status"], name: "index_service_applications_on_status"
    t.index ["verification_code"], name: "index_service_applications_on_verification_code", unique: true
  end

  create_table "settlements", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.bigint "dgi_payment_id"
    t.string "payment_order_id"
    t.decimal "total_collected", precision: 15, scale: 2, null: false
    t.decimal "partner_amount", precision: 15, scale: 2, null: false
    t.decimal "bonid_fee", precision: 15, scale: 2, null: false
    t.string "currency", default: "HTG", null: false
    t.string "form_type"
    t.string "description"
    t.string "status", default: "pending", null: false
    t.string "settlement_method"
    t.string "settlement_reference"
    t.datetime "settled_at"
    t.bigint "settled_by_admin_id"
    t.text "notes"
    t.string "batch_id"
    t.date "period_start"
    t.date "period_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_settlements_on_batch_id"
    t.index ["dgi_payment_id"], name: "index_settlements_on_dgi_payment_id"
    t.index ["partner_id", "status"], name: "idx_settlements_partner_status"
    t.index ["partner_id"], name: "index_settlements_on_partner_id"
    t.index ["payment_order_id"], name: "index_settlements_on_payment_order_id"
    t.index ["period_start", "period_end"], name: "idx_settlements_period"
    t.index ["status"], name: "index_settlements_on_status"
  end

  create_table "severity_rules", force: :cascade do |t|
    t.bigint "crime_type_id", null: false
    t.string "condition_type"
    t.jsonb "condition_value"
    t.integer "severity_modifier"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["crime_type_id", "condition_type"], name: "index_severity_rules_on_crime_type_id_and_condition_type"
    t.index ["crime_type_id"], name: "index_severity_rules_on_crime_type_id"
  end

  create_table "signature_logs", force: :cascade do |t|
    t.bigint "identity_submission_id", null: false
    t.bigint "user_id", null: false
    t.bigint "verifier_id"
    t.string "action", null: false
    t.string "signature_hash"
    t.jsonb "metadata", default: {}, null: false
    t.boolean "verified", default: false
    t.datetime "verified_at"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_signature_logs_on_action"
    t.index ["identity_submission_id"], name: "index_signature_logs_on_identity_submission_id"
    t.index ["signature_hash"], name: "index_signature_logs_on_signature_hash"
    t.index ["user_id"], name: "index_signature_logs_on_user_id"
    t.index ["verifier_id"], name: "index_signature_logs_on_verifier_id"
  end

  create_table "social_handles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "platform", default: "general"
    t.string "handle"
    t.boolean "active"
    t.date "since"
    t.date "until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "visibility"
    t.integer "verification_status"
    t.string "uid"
    t.string "access_token"
    t.string "refresh_token"
    t.datetime "expires_at"
    t.index ["user_id"], name: "index_social_handles_on_user_id"
  end

  create_table "suspect_alerts", force: :cascade do |t|
    t.bigint "user_id"
    t.string "bonid"
    t.string "name"
    t.string "alert_type", null: false
    t.integer "priority", default: 0
    t.text "description"
    t.jsonb "physical_description", default: {}
    t.string "created_by_type"
    t.bigint "created_by_id"
    t.bigint "source_incident_id"
    t.datetime "expires_at"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "priority"], name: "index_suspect_alerts_on_active_and_priority"
    t.index ["alert_type"], name: "index_suspect_alerts_on_alert_type"
    t.index ["bonid"], name: "index_suspect_alerts_on_bonid"
    t.index ["created_by_type", "created_by_id"], name: "index_suspect_alerts_on_created_by"
    t.index ["source_incident_id"], name: "index_suspect_alerts_on_source_incident_id"
    t.index ["user_id"], name: "index_suspect_alerts_on_user_id"
  end

  create_table "transaction_consents", force: :cascade do |t|
    t.bigint "citizen_id", null: false
    t.bigint "partner_id", null: false
    t.string "consent_token", null: false
    t.string "transaction_type", null: false
    t.integer "status", default: 0, null: false
    t.text "scopes", default: [], array: true
    t.decimal "amount", precision: 12, scale: 2
    t.string "currency", default: "HTG"
    t.text "description"
    t.string "reference_id"
    t.string "callback_url"
    t.string "otp_digest"
    t.integer "otp_attempts", default: 0
    t.datetime "otp_expires_at"
    t.string "notification_channel", default: "email"
    t.datetime "sms_sent_at"
    t.datetime "decided_at"
    t.string "signature"
    t.string "ip_address"
    t.jsonb "audit_log", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "liveness_session_id"
    t.decimal "liveness_confidence", precision: 5, scale: 2
    t.datetime "biometric_verified_at"
    t.integer "data_access_count", default: 0, null: false
    t.datetime "data_accessed_at"
    t.boolean "burn_after_read", default: false, null: false
    t.integer "data_access_window_minutes"
    t.index ["citizen_id", "partner_id", "reference_id"], name: "idx_tx_consent_citizen_partner_ref", unique: true
    t.index ["citizen_id"], name: "index_transaction_consents_on_citizen_id"
    t.index ["consent_token", "partner_id"], name: "idx_tx_consent_token_partner"
    t.index ["consent_token"], name: "index_transaction_consents_on_consent_token", unique: true
    t.index ["expires_at"], name: "index_transaction_consents_on_expires_at"
    t.index ["partner_id"], name: "index_transaction_consents_on_partner_id"
    t.index ["status"], name: "index_transaction_consents_on_status"
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
    t.text "qr_png_base64"
    t.integer "weight_kg"
    t.integer "height_cm"
    t.string "race"
    t.string "eye_color"
    t.string "hair_color"
    t.string "cin_unique_id"
    t.integer "birth_department_id"
    t.integer "birth_commune_id"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.bigint "partner_id"
    t.string "invitation_token"
    t.datetime "invitation_created_at"
    t.datetime "invitation_sent_at"
    t.datetime "invitation_accepted_at"
    t.integer "invitation_limit"
    t.string "invited_by_type"
    t.bigint "invited_by_id"
    t.integer "invitations_count", default: 0
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "document_issuer"
    t.boolean "active", default: true, null: false
    t.bigint "partner_branch_id"
    t.string "agent_rank"
    t.string "type"
    t.string "prefix"
    t.string "suffix"
    t.string "ninu", limit: 10
    t.datetime "last_seen_at"
    t.index ["active"], name: "index_users_on_active"
    t.index ["address_id"], name: "index_users_on_address_id"
    t.index ["agent_rank"], name: "index_users_on_agent_rank"
    t.index ["bonid"], name: "index_users_on_bonid_unique", unique: true, where: "(bonid IS NOT NULL)"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["dob"], name: "index_users_on_dob"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["invited_by_type", "invited_by_id"], name: "index_users_on_invited_by"
    t.index ["ninu"], name: "index_users_on_ninu"
    t.index ["partner_branch_id"], name: "index_users_on_partner_branch_id"
    t.index ["partner_id"], name: "index_users_on_partner_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["sex"], name: "index_users_on_sex"
    t.index ["type"], name: "index_users_on_type"
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "role_id", null: false
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "verification_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "record_type", null: false
    t.string "category"
    t.jsonb "data", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.integer "access_level", default: 0, null: false
    t.datetime "verified_at"
    t.uuid "verifier_id"
    t.string "verifier_type"
    t.string "verifier_signature"
    t.string "source", default: "self_reported", null: false
    t.text "notes"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "visibility"
    t.bigint "partner_id"
    t.index ["access_level"], name: "idx_access_level"
    t.index ["access_level"], name: "index_verification_records_on_access_level"
    t.index ["created_at"], name: "index_verification_records_on_created_at"
    t.index ["data"], name: "idx_verification_records_data_gin", using: :gin
    t.index ["data"], name: "index_verification_records_on_data", using: :gin
    t.index ["metadata"], name: "idx_verification_records_metadata_gin", where: "(metadata IS NOT NULL)", using: :gin
    t.index ["partner_id", "record_type"], name: "idx_partner_record_type"
    t.index ["partner_id"], name: "index_verification_records_on_partner_id"
    t.index ["record_type", "category"], name: "idx_verification_type_category"
    t.index ["record_type"], name: "index_verification_records_on_record_type"
    t.index ["source"], name: "idx_source"
    t.index ["status"], name: "index_verification_records_on_status"
    t.index ["user_id", "record_type"], name: "idx_user_record_type"
    t.index ["user_id", "status"], name: "idx_user_status"
    t.index ["user_id"], name: "index_verification_records_on_user_id"
    t.index ["verified_at"], name: "idx_verified_at"
    t.index ["verifier_id"], name: "index_verification_records_on_verifier_id"
    t.index ["verifier_type", "verifier_id"], name: "idx_verifier"
    t.index ["verifier_type"], name: "index_verification_records_on_verifier_type"
  end

  create_table "visitor_access_grants", force: :cascade do |t|
    t.bigint "visitor_submission_id", null: false
    t.string "token", null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_visitor_access_grants_on_token", unique: true
    t.index ["visitor_submission_id"], name: "index_visitor_access_grants_on_visitor_submission_id"
  end

  create_table "visitor_scan_events", force: :cascade do |t|
    t.bigint "visitor_submission_id"
    t.string "bon_touris_id", null: false
    t.string "input_method", default: "qr_payload", null: false
    t.boolean "ok", default: false, null: false
    t.string "status", default: "verification_failed", null: false
    t.string "message"
    t.string "actor_kind"
    t.string "actor_label"
    t.boolean "actor_verified", default: false
    t.string "ip_address"
    t.text "user_agent"
    t.string "accept_language"
    t.text "referer"
    t.string "request_id"
    t.string "country"
    t.string "region"
    t.string "city"
    t.datetime "notified_at"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bon_touris_id"], name: "index_visitor_scan_events_on_bon_touris_id"
    t.index ["notified_at"], name: "index_visitor_scan_events_on_notified_at"
    t.index ["visitor_submission_id", "occurred_at"], name: "idx_on_visitor_submission_id_occurred_at_c12dbb6195"
    t.index ["visitor_submission_id"], name: "index_visitor_scan_events_on_visitor_submission_id"
  end

  create_table "visitor_submissions", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.date "dob", null: false
    t.string "sex", null: false
    t.string "passport_number", null: false
    t.string "country_code", null: false
    t.string "purpose_of_visit", null: false
    t.string "accommodation_address"
    t.integer "stay_duration_days"
    t.integer "entry_mode", default: 0, null: false
    t.string "transport_provider", null: false
    t.jsonb "transport_details", default: {}
    t.string "bonid"
    t.datetime "expires_at"
    t.bigint "user_id"
    t.bigint "identity_submission_id"
    t.string "port_of_entry", null: false
    t.string "transport_reference"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title"
    t.string "middle_name"
    t.string "nationality"
    t.string "residence_country"
    t.string "email"
    t.string "phone"
    t.string "accommodation_name"
    t.string "accommodation_type"
    t.integer "status", default: 0, null: false
    t.string "email_otp"
    t.datetime "email_otp_sent_at"
    t.datetime "email_verified_at"
    t.string "phone_country_code"
    t.date "passport_expiry_date"
    t.string "rejection_reason"
    t.text "rejection_notes"
    t.datetime "rejected_at"
    t.bigint "rejected_by_admin_id"
    t.datetime "approved_at"
    t.bigint "approved_by_admin_id"
    t.text "visitor_qr_png_base64"
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "selfie_captured_at"
    t.jsonb "liveness_metadata", default: {}
    t.date "entry_date"
    t.date "arrival_date"
    t.index ["bonid"], name: "index_visitor_submissions_on_bonid", unique: true
    t.index ["country_code"], name: "index_visitor_submissions_on_country_code"
    t.index ["email"], name: "index_visitor_submissions_on_email"
    t.index ["email_otp"], name: "index_visitor_submissions_on_email_otp"
    t.index ["entry_mode", "transport_provider"], name: "index_visitor_submissions_on_entry_mode_and_transport_provider"
    t.index ["entry_mode"], name: "index_visitor_submissions_on_entry_mode"
    t.index ["identity_submission_id"], name: "index_visitor_submissions_on_identity_submission_id"
    t.index ["passport_number"], name: "index_visitor_submissions_on_passport_number"
    t.index ["public_id"], name: "index_visitor_submissions_on_public_id", unique: true
    t.index ["status"], name: "index_visitor_submissions_on_status"
    t.index ["transport_provider"], name: "index_visitor_submissions_on_transport_provider"
    t.index ["user_id"], name: "index_visitor_submissions_on_user_id"
  end

  create_table "voter_eligibility_records", force: :cascade do |t|
    t.bigint "bonvote_election_id", null: false
    t.bigint "user_id", null: false
    t.string "bonid", null: false
    t.string "cin_number"
    t.string "department_code", null: false
    t.integer "commune_id"
    t.string "constituency_name"
    t.string "status", default: "eligible", null: false
    t.string "channel", default: "domestic"
    t.string "ineligibility_reason"
    t.boolean "has_voted", default: false, null: false
    t.datetime "voted_at"
    t.datetime "verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bonvote_election_id", "bonid"], name: "idx_voter_election_bonid", unique: true
    t.index ["bonvote_election_id", "department_code"], name: "idx_voter_election_dept"
    t.index ["bonvote_election_id"], name: "index_voter_eligibility_records_on_bonvote_election_id"
    t.index ["has_voted"], name: "index_voter_eligibility_records_on_has_voted"
    t.index ["status"], name: "index_voter_eligibility_records_on_status"
    t.index ["user_id"], name: "index_voter_eligibility_records_on_user_id"
  end

  create_table "waitlist_signups", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "email", null: false
    t.string "phone"
    t.string "signup_type", default: "citizen"
    t.bigint "commune_id"
    t.string "sector"
    t.string "referral_code"
    t.string "invite_code_used"
    t.boolean "diaspora", default: false
    t.string "country_of_residence"
    t.string "organization_name"
    t.string "status", default: "waiting"
    t.datetime "invited_at"
    t.datetime "converted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "rank"
    t.string "unit_type"
    t.string "unit_name"
    t.index ["commune_id"], name: "index_waitlist_signups_on_commune_id"
    t.index ["email"], name: "index_waitlist_signups_on_email", unique: true
    t.index ["referral_code"], name: "index_waitlist_signups_on_referral_code", unique: true
    t.index ["signup_type"], name: "index_waitlist_signups_on_signup_type"
    t.index ["status"], name: "index_waitlist_signups_on_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "addresses", "communal_sections"
  add_foreign_key "addresses", "partners"
  add_foreign_key "api_access_logs", "partners"
  add_foreign_key "api_access_logs", "users"
  add_foreign_key "api_webhook_events", "partners"
  add_foreign_key "arrondissements", "departments"
  add_foreign_key "bank_profiles", "banks"
  add_foreign_key "bank_profiles", "users"
  add_foreign_key "bonid_aliases", "users"
  add_foreign_key "bonvote_elections", "bonvote_elections", column: "parent_election_id"
  add_foreign_key "border_entries", "officers"
  add_foreign_key "border_entries", "partners"
  add_foreign_key "border_entries", "visitor_submissions"
  add_foreign_key "citizen_profiles", "users"
  add_foreign_key "citizen_sessions", "citizen_profiles"
  add_foreign_key "citizen_sessions", "users"
  add_foreign_key "communal_sections", "communes"
  add_foreign_key "communes", "arrondissements"
  add_foreign_key "communes", "departments"
  add_foreign_key "consent_grants", "partners"
  add_foreign_key "consent_grants", "users", column: "citizen_id"
  add_foreign_key "consent_grants", "users", column: "granted_by_id"
  add_foreign_key "consent_grants", "users", column: "revoked_by_id"
  add_foreign_key "credit_ledger_entries", "partners"
  add_foreign_key "crime_hotspots", "communes"
  add_foreign_key "crime_hotspots", "crime_categories"
  add_foreign_key "crime_types", "crime_categories"
  add_foreign_key "dgi_payments", "users"
  add_foreign_key "dgi_payments", "verification_records"
  add_foreign_key "election_accreditations", "bonvote_elections", column: "election_id"
  add_foreign_key "election_accreditations", "election_bodies", column: "assigned_body_id"
  add_foreign_key "election_accreditations", "users"
  add_foreign_key "election_ballots", "bonvote_elections", column: "election_id"
  add_foreign_key "election_bodies", "bonvote_elections", column: "election_id"
  add_foreign_key "election_bodies", "election_bodies", column: "parent_body_id"
  add_foreign_key "election_candidates", "admin_users", column: "approved_by_id"
  add_foreign_key "election_candidates", "admin_users", column: "rejected_by_id"
  add_foreign_key "election_candidates", "bonvote_elections", column: "election_id"
  add_foreign_key "election_candidates", "election_constituencies"
  add_foreign_key "election_candidates", "election_party_registrations", column: "party_registration_id"
  add_foreign_key "election_candidates", "users"
  add_foreign_key "election_constituencies", "bonvote_elections", column: "election_id"
  add_foreign_key "election_disputes", "bonvote_elections", column: "election_id"
  add_foreign_key "election_disputes", "election_bodies"
  add_foreign_key "election_disputes", "election_constituencies", column: "constituency_id"
  add_foreign_key "election_party_registrations", "bonvote_elections", column: "election_id"
  add_foreign_key "election_party_registrations", "users"
  add_foreign_key "election_signatures", "bonvote_elections", column: "election_id"
  add_foreign_key "election_staff_assignments", "bonvote_elections", column: "election_id"
  add_foreign_key "election_staff_assignments", "election_bodies"
  add_foreign_key "election_staff_assignments", "users"
  add_foreign_key "electoral_calendars", "bonvote_elections", on_delete: :cascade
  add_foreign_key "emergency_contacts", "users"
  add_foreign_key "failed_bonid_lookups", "officers"
  add_foreign_key "family_members", "communes", column: "birth_commune_id"
  add_foreign_key "family_members", "departments", column: "birth_department_id"
  add_foreign_key "family_members", "users"
  add_foreign_key "family_members", "users", column: "linked_user_id", on_delete: :nullify
  add_foreign_key "health_profiles", "users"
  add_foreign_key "identity_submissions", "partners"
  add_foreign_key "identity_submissions", "users"
  add_foreign_key "incident_links", "incident_reports"
  add_foreign_key "incident_links", "incident_reports", column: "linked_incident_id"
  add_foreign_key "incident_reports", "crime_types", column: "crime_type_record_id"
  add_foreign_key "incident_reports", "officers"
  add_foreign_key "incident_reports", "partners"
  add_foreign_key "incident_reviews", "admin_users", column: "assigned_by_id"
  add_foreign_key "incident_reviews", "admin_users", column: "reviewer_id"
  add_foreign_key "incident_reviews", "incident_reports"
  add_foreign_key "invite_codes", "communes"
  add_foreign_key "invite_codes", "partners"
  add_foreign_key "invite_codes", "users"
  add_foreign_key "local_contacts", "users"
  add_foreign_key "local_contacts", "visitor_submissions"
  add_foreign_key "name_change_requests", "admin_users", column: "reviewed_by_id"
  add_foreign_key "name_change_requests", "users"
  add_foreign_key "o_auth_access_tokens", "partners"
  add_foreign_key "o_auth_access_tokens", "users", column: "citizen_id"
  add_foreign_key "oauth_applications", "partners"
  add_foreign_key "oauth_authorization_codes", "oauth_applications"
  add_foreign_key "oauth_authorization_codes", "users"
  add_foreign_key "oauth_events", "oauth_applications"
  add_foreign_key "oauth_events", "users"
  add_foreign_key "officer_complaints", "arrondissements"
  add_foreign_key "officer_complaints", "communal_sections"
  add_foreign_key "officer_complaints", "communes"
  add_foreign_key "officer_complaints", "departments"
  add_foreign_key "officer_complaints", "users"
  add_foreign_key "officer_metrics", "officers"
  add_foreign_key "officers", "arrondissements"
  add_foreign_key "officers", "communal_sections"
  add_foreign_key "officers", "communes"
  add_foreign_key "officers", "departments"
  add_foreign_key "officers", "partners"
  add_foreign_key "officers", "users"
  add_foreign_key "partner_access_logs", "admin_users"
  add_foreign_key "partner_access_logs", "partners"
  add_foreign_key "partner_api_logs", "partners"
  add_foreign_key "partner_applications", "partners"
  add_foreign_key "partner_audit_logs", "partners"
  add_foreign_key "partner_branches", "partners"
  add_foreign_key "partner_payments", "partner_plans"
  add_foreign_key "partner_payments", "partners"
  add_foreign_key "partner_schemas", "admin_users", column: "approved_by_id"
  add_foreign_key "partner_schemas", "partners"
  add_foreign_key "partners", "partner_plans"
  add_foreign_key "permissions_roles", "permissions"
  add_foreign_key "permissions_roles", "roles"
  add_foreign_key "person_involvements", "addresses"
  add_foreign_key "person_involvements", "incident_reports"
  add_foreign_key "person_involvements", "users"
  add_foreign_key "person_involvements", "visitor_submissions"
  add_foreign_key "physical_profiles", "users"
  add_foreign_key "plan_add_ons", "partner_plans"
  add_foreign_key "plan_features", "partner_plans"
  add_foreign_key "qr_scan_logs", "identity_submissions"
  add_foreign_key "qr_scan_logs", "officers"
  add_foreign_key "qr_scan_logs", "partners"
  add_foreign_key "qr_scan_logs", "qr_scans"
  add_foreign_key "qr_scans", "identity_submissions"
  add_foreign_key "qr_scans", "officers"
  add_foreign_key "qr_scans", "partners"
  add_foreign_key "qr_scans", "users", column: "banking_agent_id"
  add_foreign_key "related_crime_types", "crime_types"
  add_foreign_key "related_crime_types", "crime_types", column: "related_crime_type_id"
  add_foreign_key "review_comments", "admin_users"
  add_foreign_key "review_comments", "incident_reviews"
  add_foreign_key "review_comments", "person_involvements"
  add_foreign_key "reviewer_activities", "users"
  add_foreign_key "service_applications", "partner_schemas"
  add_foreign_key "service_applications", "partners"
  add_foreign_key "service_applications", "users", column: "citizen_id"
  add_foreign_key "service_applications", "users", column: "reviewed_by_id"
  add_foreign_key "settlements", "dgi_payments"
  add_foreign_key "settlements", "partners"
  add_foreign_key "severity_rules", "crime_types"
  add_foreign_key "signature_logs", "identity_submissions"
  add_foreign_key "signature_logs", "users"
  add_foreign_key "social_handles", "users"
  add_foreign_key "suspect_alerts", "incident_reports", column: "source_incident_id"
  add_foreign_key "suspect_alerts", "users"
  add_foreign_key "transaction_consents", "partners"
  add_foreign_key "transaction_consents", "users", column: "citizen_id"
  add_foreign_key "users", "addresses"
  add_foreign_key "users", "partner_branches"
  add_foreign_key "users", "partners"
  add_foreign_key "users_roles", "roles"
  add_foreign_key "users_roles", "users"
  add_foreign_key "verification_records", "partners"
  add_foreign_key "verification_records", "users"
  add_foreign_key "visitor_access_grants", "visitor_submissions"
  add_foreign_key "visitor_scan_events", "visitor_submissions"
  add_foreign_key "visitor_submissions", "identity_submissions"
  add_foreign_key "visitor_submissions", "users"
  add_foreign_key "voter_eligibility_records", "bonvote_elections", on_delete: :cascade
  add_foreign_key "voter_eligibility_records", "users"
  add_foreign_key "waitlist_signups", "communes"
end
