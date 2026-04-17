Rails.application.routes.draw do
  # ===========================================================================
  # HEALTH & MONITORING
  # ===========================================================================
  get "/up", to: "rails/health#show", as: :rails_health_check

  # ===========================================================================
  # BONGOUV — Public Receipt Verification
  # ===========================================================================
  # Scanned QR codes on DGI receipts hit this endpoint.
  # No auth required — public cryptographic verification.
  get "/v/:token", to: "bongouv/verification#show", as: :bongouv_verify

  # config/routes.rb




  # ===========================================================================
  # ROOT & PUBLIC PAGES
  # ===========================================================================
  root "main#home"

  # Landing page — pre-launch signup
  get  "/enskri",    to: "landing#index",            as: :enskri
  post "/enskri",    to: "landing#signup",            as: :enskri_signup
  get  "/enskri/confirmation", to: "landing#confirmation", as: :enskri_confirmation
  get  "/enskri/arrondissements", to: "landing#arrondissements"
  get  "/enskri/communes",        to: "landing#communes"

  # One-time secret portal (OAuth credentials)
  get "/secrets/:token", to: "one_time_secrets#show", as: :one_time_secret

  get "/start",    to: "main#start",    as: :start_verification
  get "/partners", to: "main#partners", as: :partners
  get "/pricing",  to: "main#pricing",  as: :pricing
  get "/favicon.ico", to: redirect("/assets/favicon.ico")
  # CRYPTOGRAPHIC / OFFLINE QR (BonTouris)
  get "/v", to: "public/bon_touris_verifications#show", as: :bon_touris_verify




  # Legal pages (PDF must come before HTML to avoid format conflicts)
  get "/terms.pdf",   to: "pdfs#terms",   as: :terms_pdf
  get "/privacy.pdf", to: "pdfs#privacy", as: :privacy_pdf
  get "/terms",       to: "main#terms",   as: :terms
  get "/privacy",     to: "main#privacy", as: :privacy

  # ===========================================================================
  # PUBLIC API DOCS & VERSION
  # ===========================================================================
  get "/api/version",         to: "public_api#version"
  get "/api/v1/openapi.yaml", to: "public_api#openapi"
  get "/api/v1/openapi.json", to: "public_api#openapi_json"

  mount Rswag::Api::Engine => "/api/swagger"
  mount Rswag::Ui::Engine  => "/api-docs"

  # ===========================================================================
  # PUBLIC VERIFICATION ENDPOINTS (No Auth Required)
  # ===========================================================================
  # get "/verify/:verification_token", to: "public/verifications#show", as: :public_verification
  # get "/verify/:public_token",       to: "citizens/verifications#show", as: :verify_public_token
  # get "/v", to: "public/bon_touris_verifications#show", as: :public_bon_touris_verify

  # ✅ OPTIONAL: public "stub" page that shows NO STATUS (safe for camera)
  get "/verify", to: "public/verifications#stub", as: :public_verify_stub

  # ✅ Public: IGPNH complaint certificate verification (no auth required)
  # QR code on printed certificates points here so any official can scan & verify
  get "/complaints/verify/:tracking_number",
      to: "public/complaint_verifications#show",
      as: :public_complaint_verify

  # ✅ Public: PNH officer incident report verification (no auth required)
  # QR code on printed reports points here so judges/lawyers/prosecutors can verify
  # Maps to verifie.pnh.gouv.ht/rapport/:report_id in production
  get "/reports/verify/:report_id",
      to: "public/incident_report_verifications#show",
      as: :public_incident_report_verify

  # ===========================================================================
  # MONCASH PAYMENT CALLBACKS
  # ===========================================================================
  namespace :moncash do
    get "success", to: "callbacks#success", as: :success
    get "error",   to: "callbacks#error",   as: :error
  end

  # ✅ Partner-only QR resolve (web session)
  post "/qr/resolve", to: "partner_portal/qr_scans#resolve", as: :qr_resolve

  # ✅ Partner-only verification view page
  namespace :partner_portal do
    get "verify/:verification_token", to: "verifications#show", as: :verify_token
  end


# config/routes.rb
namespace :public do
  resources :visitors, only: %i[new create] do
    collection do
      get  :get_started
      post :continue
      post :scan_passport       # Passport OCR via AWS Textract
      post :liveness_session    # Create AWS Rekognition liveness session
      get  :liveness_results    # Trigger async liveness result processing
      get  :liveness_status     # Poll for liveness results
      post :face_compare        # Compare selfie vs passport photo
      post :manual_selfie       # Low-bandwidth fallback selfie
    end

    member do
      # ============================================================
      # STEP 2 — Email verification
      # ============================================================
      get  :verify_email
      post :verify_email
      post :resend_otp

      # ============================================================
      # STEP 3 — Document upload
      # ============================================================
      get  :documents
      post :documents, action: :documents_submit

      # ============================================================
      # STEP 4 — Final status / approved view
      # QR + Certificate toggle lives here
      # ============================================================
      get :success

      # ============================================================
      # Certificate / QR download (approved only)
      # ============================================================
      get :download_pdf

      # ============================================================
      # Reapply (SECURE — POST only)
      # ============================================================
      post :reapply
    end
  end
end

  #  ====================================================================
  # DEVISE AUTH (Citizens, Officers, Partner Admins, Reviewers, Admins)
  # ===========================================================================

  # Citizens
  devise_for :citizens,
    class_name: "User",
    path: "citizens",
    controllers: {
      sessions:      "citizens/sessions",
      passwords:     "citizens/passwords",
      registrations: "citizens/registrations"
    }

  devise_scope :citizen do
    get  "citizens/otp_sign_in", to: "citizens/sessions#otp_sign_in", as: :citizens_otp_sign_in
    post "citizens/otp_sign_in", to: "citizens/sessions#create_otp"
    get  "citizens/verify_otp",  to: "citizens/sessions#verify_otp", as: :citizens_verify_otp
    post "citizens/verify_otp",  to: "citizens/sessions#verify_otp"
    post "citizens/resend_otp",  to: "citizens/sessions#resend_otp", as: :citizens_resend_otp
  end

  # Officers
  devise_for :officer,
    class_name: "Officer",
    path: "officers",
    controllers: {
      sessions:      "officers/sessions",
      passwords:     "officers/passwords",
      registrations: "officers/registrations",
      invitations:   "officers/invitations",
      confirmations: "officers/confirmations"
    }

  devise_scope :officer do
    get "officers/invalid", to: redirect("/reviewer/sign_in")
  end

  # Partner Admins
  devise_for :partner_admins,
    class_name: "User",
    path: "partner_admins",
    controllers: {
      sessions:    "partner_portal/partner_admins/sessions",
      passwords:   "partner_portal/partner_admins/passwords",
      invitations: "partner_portal/partner_admins/invitations"
    },
    skip: [ :registrations ]

  # Reviewers
  devise_for :reviewers,
    class_name: "User",
    path: "reviewer",
    controllers: {
      sessions:  "reviewers/sessions",
      passwords: "reviewers/passwords"
    },
    skip: [ :registrations ]

  # Admin Users
  devise_for :admin_users,
    class_name: "AdminUser",
    path: "admin",
    controllers: {
      sessions:  "admin/sessions",
      passwords: "admin/passwords"
    },
    skip: [ :registrations ]

  # ===========================================================================
  # ADMIN
  # ===========================================================================
  namespace :admin do
    root to: "dashboards#index"

    resources :dashboards, only: [] do
      collection do
        get :charts
      end
    end

    # Electoral Offices (BED / BEK) — CEP's physical field offices.
    # CRUD managed by CEP administrators through the Command Center;
    # controller lives under Election::Admin:: to mirror ElectionsController.
    resources :electoral_offices, controller: "/election/admin/electoral_offices"

    # Election Admin (CEP Dashboard)
    # Controller: Election::Admin::ElectionsController
    get    "election/:id",          to: "/election/admin/elections#show",     as: :election_election
    get    "election/:id/snapshot",  to: "/election/admin/elections#snapshot",  as: :election_election_snapshot
    post   "election/:id/decrypt",   to: "/election/admin/elections#decrypt",   as: :election_election_decrypt
    get    "election/:id/multi_sig", to: "/election/admin/elections#multi_sig", as: :election_election_multi_sig
    post   "election/:id/sign",      to: "/election/admin/elections#sign",      as: :election_election_sign
    get    "election/:id/results",   to: "/election/admin/elections#results",   as: :election_election_results
    # Signed oath audit trail — one row per (user, election, oath_version)
    get    "election/:id/oaths",     to: "/election/admin/elections#oaths",    as: :election_election_oaths
    # Edit election — toggle policy flags (online voting, digital enrollment)
    get    "election/:id/edit",      to: "/election/admin/elections#edit",     as: :edit_election_election
    patch  "election/:id",           to: "/election/admin/elections#update"
    # Certify election — stamps winners + locks results
    post   "election/:id/certify",   to: "/election/admin/elections#certify",  as: :election_election_certify

    # Candidate nomination review (Gap 6).
    # Submission happens in the partner portal; CEP approval happens here.
    get  "election/:election_id/candidates",                  to: "/election/admin/candidates#index",        as: :election_election_candidates
    get  "election/:election_id/candidates/:id",              to: "/election/admin/candidates#show",         as: :election_election_candidate
    post "election/:election_id/candidates/:id/start_review", to: "/election/admin/candidates#start_review", as: :start_review_election_election_candidate
    post "election/:election_id/candidates/:id/approve",      to: "/election/admin/candidates#approve",      as: :approve_election_election_candidate
    post "election/:election_id/candidates/:id/reject",       to: "/election/admin/candidates#reject",       as: :reject_election_election_candidate

    # Party / grouping registration review (Gap 7).
    get  "election/:election_id/party_registrations",                  to: "/election/admin/party_registrations#index",        as: :election_election_party_registrations
    get  "election/:election_id/party_registrations/:id",              to: "/election/admin/party_registrations#show",         as: :election_election_party_registration
    post "election/:election_id/party_registrations/:id/start_review", to: "/election/admin/party_registrations#start_review", as: :start_review_election_election_party_registration
    post "election/:election_id/party_registrations/:id/approve",      to: "/election/admin/party_registrations#approve",      as: :approve_election_election_party_registration
    post "election/:election_id/party_registrations/:id/reject",       to: "/election/admin/party_registrations#reject",       as: :reject_election_election_party_registration

    # (UNCHANGED — all your admin routes preserved)
    resources :partners, param: :uuid do
      member do
        post :approve
        post :reject
        post :suspend
        post :restore
        post :soft_delete
        post :rotate_api_key
        post :regenerate_qr
        post :resend_verification_email
        post :resend_invitation
        get  :geocode_address
      end
      collection { get :invite_options }
    end

    resources :partner_schemas
    resources :schemas, except: [ :show ] do
      collection { get :select_partners }
      member     { post :assign_template }
    end

    resources :identity_submissions, only: [ :index, :show, :update ], param: :uuid do
      member do
        patch :approve
        patch :reject
        patch :approve_bin
        patch :reject_bin
        patch :approve_reset
        patch :reject_reset
        post  :regenerate_qr
        post  :verify_signature
        post  :retry_face_match
      end
      collection do
        post  :bulk_update
        post  :fallback_lookup
        patch :bulk_approve_bin
        patch :bulk_reject_bin
      end
    end

    # NAME CHANGE REQUESTS
    resources :name_change_requests, only: [ :index, :show ] do
      member do
        patch :approve
        patch :reject
      end
    end

    # VISITOR / TOURIST SUBMISSIONS (BonTourist)
    resources :visitor_submissions, only: [ :index, :show ] do
      member do
        post :approve
        post :reject
        post :resend_certificate
      end
    end

    resources :visitor_analytics, only: :index

    resources :incident_reports, only: [ :index, :show ] do
      member do
        post :approve
        post :flag
        get  :print
        get  :download_pdf
        get  :share
      end
    end

    # Incident Analytics Dashboard
    resources :incident_analytics, only: [ :index ] do
      collection do
        get :hotspots
        get :officers
        get :crime_types
        post :generate_hotspot_report
        post :generate_officer_metrics
      end
    end

    resources :reviewers, only: [ :index, :new, :create, :destroy ] do
      collection do
        post :lookup
        get  :bulk_new
        post :bulk_create
        get  :activity
      end
    end

    resources :officer_invitations, only: [ :new, :create ]
    get  "officer_bulk_invitations/new", to: "officer_bulk_invitations#new"
    post "officer_bulk_invitations",     to: "officer_bulk_invitations#create"

    resources :qr_scan_logs, :partner_access_logs, :webhook_events, :oauth_events,
              :partner_audit_logs, only: [ :index, :show ]

    resources :api_usage, only: [ :index ]
    resources :qr_scans, only: [ :index ]

    # Billing
    get "billing",               to: "billing#index",         as: :billing
    get "billing/credit_ledger", to: "billing#credit_ledger", as: :billing_credit_ledger
    get "billing/payments",      to: "billing#payments",      as: :billing_payments

    # Settlements
    resources :settlements, only: [ :index, :show ] do
      collection do
        post :settle_batch
      end
    end

    resources :guidelines, only: [ :index ] do
      collection { post :confirm }
    end

    resources :waitlist_signups, only: [ :index, :show ] do
      member do
        post :invite
        post :convert
      end
      collection do
        post :bulk_invite
        get :communes
      end
    end

    resources :invite_codes, only: [ :index, :new, :create, :show, :destroy ] do
      member do
        post :toggle_active
      end
      collection do
        post :bulk_generate
      end
    end
  end

  # ===========================================================================
  # REVIEWERS
  # ===========================================================================
  namespace :reviewers do
    root to: "dashboard#index"
    get  "dashboard", to: "dashboard#index"

    resources :identity_submissions, only: [ :index, :show, :update ] do
      member do
        patch :approve
        patch :reject
        patch :approve_bin
        patch :reject_bin
        patch :approve_reset
        patch :reject_reset
        post  :regenerate_qr
        post  :verify_signature
      end
      collection do
        post :bulk_update
        post :fallback_lookup
      end
    end

    resources :analytics,     only: [ :show ]
    resources :audit_logs,    only: [ :index ]
    resources :notifications, only: [ :index ]
  end

  # ===========================================================================
  # CITIZENS
  # ===========================================================================
  # Family link confirmation (public — token is auth, no login required)
  get  "family/confirm", to: "citizens/family_links#confirm", as: :confirm_family_link
  get  "family/deny",    to: "citizens/family_links#deny",    as: :deny_family_link

  namespace :citizens do
    root to: "dashboard#index"
    get  "dashboard", to: "dashboard#index"

    # ✅ Support Center Route
    get "support", to: "support#index", as: :support

    # ✅ Unified Activity Feed (Aktivite) — consolidates scans, consents,
    # transaction consents, and service applications into one timeline.
    get "activity", to: "activity#index", as: :activity

    resource  :profile, only: [ :new, :create, :show, :edit, :update ]
    resources :verification_records
    resources :addresses, only: [ :create ]
    resources :consents,  only: [ :index, :destroy ]
    resources :transaction_consents, only: [ :index ], param: :consent_token do
      member do
        post :decide
        post :liveness_decide
      end
    end

    resources :identity_submissions, param: :public_token do
      collection do
        post :request_new
        get  :verify
        get  :scan_history
        post :liveness_session
        get  :liveness_results
        get  :liveness_status
        post :face_compare
        post :manual_selfie
      end
      member do
        get  :verified_profile
        post :refresh_qr
      end
    end

    resources :name_change_requests, only: [ :new, :create ]

    # Officer Complaints (Plaintes contre un policier — IGPNH)
    # URLs use :uuid (SecureRandom.uuid, 2^122) instead of the short tracking_number
    # to prevent brute-force enumeration and IDOR attacks.
    resources :officer_complaints, only: [ :index, :new, :create, :show ],
              param: :uuid do
      member do
        get :certificate  # Downloadable filing certificate
      end
      collection do
        get :fetch_witness  # BonID/BonTouris suffix lookup for witness autofill
        # Backward compat: redirect old tracking_number-based URLs (e.g., from printed next-steps)
        get "by_ref/:tracking_number/certificate",
            action: :certificate_by_ref,
            as:     :certificate_by_ref
      end
    end

    # DGI Self-Service Filing (Citizen files their own tax forms)
    resources :dgi, only: [ :index, :new, :create, :show ], controller: "dgi" do
      collection do
        post :save_draft
      end
      member do
        get  :resubmit
        post :update_resubmit
      end
    end

    # DGI Payments
    resources :dgi_payments, only: [ :index, :show ], param: :order_id, controller: "dgi_payments" do
      member do
        post :pay
        get  :receipt
      end
      collection do
        get :moncash_callback
        get :zellus_callback
      end
    end

    # Browse Partner Services
    resources :services, only: [ :index, :show ], param: :slug

    # Service Applications — citizen applies to partner services
    resources :service_applications, only: [ :index, :show, :create, :update ] do
      member do
        post :submit
        get  :receipt
      end
      collection do
        post :auto_save
        get  :zellus_callback
      end
    end
    get "apply/:partner_slug/:form_code", to: "service_applications#new", as: :apply_service
    get "service/:partner_slug/:form_code", to: "services#detail", as: :service_detail

    # ── Election (Citizen Voting) ──────────────────────────────
    namespace :election do
      get "kalandriye", to: "calendar#index", as: :calendar

      # Self-service enrollment / registration-status page
      get  "enskri", to: "enrollment#show",   as: :enrollment
      post "enskri", to: "enrollment#create"

      # BonID-generated voter receipt (PDF with QR for poll workers)
      get  "resi/telechaje", to: "receipts#download", as: :receipt_download
      get  "resi/enprime",   to: "receipts#print",    as: :receipt_print

      # BED/BEK locator — where citizens can go for walk-in help
      get  "biwo", to: "offices#index", as: :offices

      # Voting flow (multi-step wizard)
      get  "vote",             to: "vote#eligibility", as: :vote
      get  "vote/seman",       to: "vote#oath",        as: :vote_oath
      post "vote/seman",       to: "vote#sign_oath",   as: :vote_sign_oath
      post "vote/begin",       to: "vote#begin",       as: :vote_begin
      post "vote/resume",      to: "vote#resume",      as: :vote_resume
      get  "vote/ballot",      to: "vote#ballot",      as: :vote_ballot
      post "vote/cast",        to: "vote#cast",        as: :vote_cast
      get  "vote/receipt",     to: "vote#receipt",      as: :vote_receipt

      # Verify my vote
      get  "verifye",          to: "verify#index",      as: :verify
      post "verifye",          to: "verify#check",      as: :verify_check

      # Results
      get  "rezilta",          to: "results#index",     as: :results
    end

    # Private Services (legacy — kept for backward compat)
    resources :bank_services, only: [ :index ]
    resources :bill_payments, only: [ :index ]
  end


  # ===========================================================================
  # OFFICERS / IDPOL
  # ===========================================================================
  namespace :officers do
    # Onboarding for new officers (no Officer record yet)
    get   "onboarding", to: "onboarding#new"
    post  "onboarding", to: "onboarding#create"
    patch "onboarding", to: "onboarding#create"

    # Officer Guidelines (must acknowledge before accessing dashboard)
    get  "guidelines", to: "guidelines#index", as: :guidelines
    post "guidelines/confirm", to: "guidelines#confirm", as: :confirm_guidelines

    get "dashboard",             to: "dashboard#index"
    get "dashboard/drafts",      to: "dashboard#drafts"
    get "dashboard/crime_reports", to: "dashboard#crime_reports"
    get "dashboard/recent_scans",  to: "dashboard#recent_scans"
    get "dashboard/failed_scans",  to: "dashboard#failed_scans"
    get "dashboard/:id",         to: "dashboard#show"

    get "profile/edit", to: "profiles#edit"
    patch "profile",      to: "profiles#update"

    resources :border_entries, only: [ :index, :create ] do
      member { patch :mark_exit }
    end

    resources :incident_reports do
      collection do
        get :bonid_lookup_manual
        get :export_csv
      end
      member do
        get  :preview       # read-only pre-submit preview with signature checkbox
        post :submit        # officer attests and transitions draft → submitted
        post :approve
        post :flag
        get  :print
        get  :download_pdf
        get  :share
      end
    end

    resources :tickets
    # BonID lookups - only create and confirm actions for officers
    # Index/show/failed are for partner admin only
    resources :bonid_lookups, only: [ :create ] do
      member do
        post :confirm
      end
    end
    post "bonid_lookup", to: "bonid_lookups#create"

    get  "scan",         to: "scans#new"
    post "scan",         to: "scans#create"
    post "scan_qrcode",  to: "scans#create_qrcode"
    get  "suspect_preview", to: "suspects#preview"

    resources :person_involvements, only: [] do
      collection { get :fetch_identity }
    end

    # Analytics Dashboard
    get "analytics", to: "analytics#index", as: :analytics
    get "analytics/crime_breakdown", to: "analytics#crime_breakdown", as: :analytics_crime_breakdown
    get "analytics/hot_zones", to: "analytics#hot_zones", as: :analytics_hot_zones
    get "analytics/demographics", to: "analytics#demographics", as: :analytics_demographics
    get "analytics/geographic", to: "analytics#geographic", as: :analytics_geographic
    get "analytics/temporal", to: "analytics#temporal", as: :analytics_temporal
    get "analytics/seasonal", to: "analytics#seasonal", as: :analytics_seasonal
    get "analytics/performance", to: "analytics#performance", as: :analytics_performance
    get "analytics/chart_data", to: "analytics#chart_data", as: :analytics_chart_data
    get "analytics/crime_location", to: "analytics#crime_location", as: :analytics_crime_location
    get "analytics/incident_reports/bonid", to: "analytics#incident_reports_bonid", as: :analytics_incident_reports_bonid
    get "analytics/incident_reports/bontouris", to: "analytics#incident_reports_bontouris", as: :analytics_incident_reports_bontouris
  end

  # ===========================================================================
  # UNIFIED PARTNER PORTAL (Banking Removed)
  # ===========================================================================
  namespace :partner_portal do
    root to: redirect("/partner_portal/dashboard")

    get "dashboard", to: "dashboard#index"

    # Profile completion for minimal signups (PNH)
    get "profile/complete", to: "profile_completion#index", as: :profile_completion
    patch "profile/complete", to: "profile_completion#update"

    # Guidelines acceptance gate (all verified partners)
    get  "guidelines", to: "guidelines_acceptance#index", as: :guidelines
    post "guidelines/accept", to: "guidelines_acceptance#accept", as: :guidelines_accept

    resources :access_logs, only: [ :index ]
    resources :partner_audit_logs, only: [ :index, :show ]
    resources :settings, only: [ :index, :update ]
    resources :metrics,     only: [ :show ]

    # Default partner features
    resources :scans, only: [ :index, :show ], controller: "scans"
    resources :bonid_lookups, only: [ :create ] do
      member { post :confirm }
    end
    resources :verifications, only: [ :index, :show ]

    # ── DGI Forms (Cashier Flow) ──────────────────────────
    # Fiscal receipts (general)
    resources :fiscal_receipts, only: [ :index, :new, :create, :show ] do
      member do
        get :receipt  # printable receipt view
      end
    end

    # Formulaire A — NIF Registration (gateway form for individuals)
    resources :nif_registrations, only: [ :index, :new, :create, :show ]

    # Formulaire B — Business Registration (gateway form for businesses)
    resources :business_registrations, only: [ :index, :new, :create, :show ]

    # Patente — Annual Business License Tax (DGI-F008)
    resources :patente_declarations, only: [ :index, :new, :create, :show ]

    # TCA — Monthly Sales Tax
    resources :tca_declarations, only: [ :index, :new, :create, :show ]

    # RAS IR — Monthly Income Withholding Tax
    resources :ras_ir_declarations, only: [ :index, :new, :create, :show ]

    # DGI Review Queue — Citizen-filed declarations pending approval
    resources :dgi_review, only: [ :index, :show ], controller: "dgi_review" do
      member do
        post :approve
        post :reject
      end
    end

    # DGI Cash/Bank Payment Confirmation
    resources :dgi_cash_payments, only: [ :index ], controller: "dgi_cash_payments" do
      member do
        post :confirm
      end
      collection do
        get :lookup
      end
    end

    # ── Service Builder (all sectors) ──────────────────────
    resources :services, only: [ :index, :new, :create, :edit, :update, :destroy ] do
      member do
        patch :toggle
        patch :publish
        get :version_history
      end
      collection do
        get :templates
      end
    end

    # Citizen submissions — partner admin reviews & approves/rejects
    resources :submissions, only: [ :index, :show ], controller: "submissions" do
      member do
        patch :approve
        patch :reject
        patch :check_in
        post  :add_note
      end
      collection do
        get  :export
        get  :agent_form     # Agent fills form on behalf of citizen
        post :agent_create   # Agent submits form on behalf of citizen
        patch :agent_update  # Agent saves form data (step-by-step)
      end
    end

    # Unified team management (all sectors except law enforcement)
    resources :team, only: [ :index, :new, :create, :destroy ] do
      collection do
        post :lookup
      end
      member do
        patch :suspend
        patch :reactivate
        patch :update_role
      end
    end

    # Elections (CEP — create & manage)
    resources :elections, only: [ :index, :new, :create, :show ], controller: "elections" do
      member do
        post :open_election
        post :close_election
        post :certify_election
        post :generate_calendar
      end
    end

    # Electoral Calendar (CEP)
    get "electoral_calendar", to: "electoral_calendar#index", as: :electoral_calendar

    # CEP Election Pages (partner portal access)
    get "election/:id/tablo",     to: "election_dashboard#show",      as: :election_tablo
    get "election/:id/multi_sig", to: "election_dashboard#multi_sig", as: :election_multi_sig
    get "election/:id/results",   to: "election_dashboard#results",   as: :election_results

    # Voter Eligibility Lookup (CEP)
    get  "voter_eligibility", to: "voter_eligibility#index", as: :voter_eligibility
    post "voter_eligibility/lookup", to: "voter_eligibility#lookup", as: :voter_eligibility_lookup

    # Voter Registry / Lis Elektoral (CEP)
    get  "voter_registry", to: "voter_registry#index", as: :voter_registry
    post "voter_registry/build", to: "voter_registry#build", as: :voter_registry_build

    # Polling Centers (Sant Vòt) — CEP + Consulate roster + CSV import
    get  "polling_centers",          to: "polling_centers#index",          as: :polling_centers
    get  "polling_centers/import",   to: "polling_centers#import",         as: :polling_centers_import
    post "polling_centers/import",   to: "polling_centers#process_import"
    get  "polling_centers/template", to: "polling_centers#template",       as: :polling_centers_template,
                                     defaults: { format: :csv }

    # Party Registration (CEP — Article 143)
    resources :party_registrations, only: [ :index, :show, :new, :create ] do
      member do
        patch :update_documents
        patch :start_review
        patch :approve
        patch :reject
      end
    end

    # Candidate Registration (CEP)
    resources :candidate_registrations, only: [ :index, :show, :new, :create ] do
      member do
        post :approve
        post :reject
        post :start_review
      end
    end

    get "analytics", to: "analytics#index"
    resources :api_keys, only: [ :index, :create, :destroy ] do
      post :generate_token, on: :collection
      post :rotate_oauth_secret, on: :collection
    end

    # Billing
    resource :billing, only: [ :show ], controller: "billing" do
      get :history, on: :member
    end

    # Credit Wallet (prepaid top-up)
    resource :credits, only: [ :show ], controller: "credits" do
      post :top_up, on: :member
      post :reconcile, on: :member
    end

    namespace :partner_admin do
      resource :profile, only: [ :edit, :update ]
    end

    # Law Enforcement partners
    namespace :law_enforcement do
      get "dashboard", to: "dashboard#index"
      post "dashboard/toggle_alert", to: "dashboard#toggle_alert"
      get "search", to: "search#index"
      resources :officers, only: [ :index, :show, :new, :create ] do
        member do
          post :revoke
          post :reactivate
        end
      end
      resources :incident_reports do
        member do
          post :approve
          post :reject
          post :escalate
          post :request_info
        end
      end
      resources :tickets
      resources :api_keys, only: [ :index, :create, :destroy ] do
        member { post :regenerate }
      end
      resources :records, only: [ :show ] do
        member { patch :verify }
      end
      # Officer invitations (require verified BonID)
      resources :officer_invitations, only: [ :new, :create ] do
        collection do
          post :lookup
          get  :bulk_new
          post :bulk_create
        end
      end
    end
  end


  # === Team Invitation Acceptance (public — no auth required) ===
  get  "/team/invitation/accept", to: "partner_portal/team_invitations#show",   as: :accept_team_invitation
  put  "/team/invitation/accept", to: "partner_portal/team_invitations#update"

  # ===========================================================================
  # ELECTION PUBLIC ROUTES (no auth required)
  # ===========================================================================
  get "/election/verify",   to: "election/audit#verify",    as: :election_audit_verify
  get "/election/snapshot",  to: "election/audit#snapshot",  as: :election_audit_snapshot
  get "/election/results",      to: "election/public#results",      as: :election_public_results
  get "/election/celebration",  to: "election/public#celebration",  as: :election_public_celebration
  get "/election/live_stats",   to: "election/public#live_stats",   as: :election_live_stats
  get "/election/whitepaper",   to: "election/public#whitepaper",   as: :election_whitepaper
  get "/election/livreblanc",   to: "election/public#livreblanc",   as: :election_livreblanc
  post "/election/feedback",       to: "election/pilot_feedback#create", as: :election_pilot_feedback
  get  "/election/feedback/stats",  to: "election/pilot_feedback#stats",  as: :election_pilot_feedback_stats

  # ===========================================================================
  # PARTNER EMAIL VERIFICATION ROUTES
  # ===========================================================================
  get "/partners/verify",              to: "partners/verifications#verify",   as: :partners_verify
  get "/partners/verification/success", to: "partners/verifications#success", as: :partners_verification_success
  get "/partners/verification/error",   to: "partners/verifications#error",   as: :partners_verification_error

  # ===========================================================================
  # PARTNER SIGNUP FLOW (Unified Form)
  # ===========================================================================
  resources :partners, only: [ :new, :create, :show ], param: :uuid

  # ===========================================================================
  # PUBLIC API (unchanged)
  # ===========================================================================
  namespace :api do
    namespace :v1 do
      match "citizen/approve_consent", to: "citizen/consent_grants#approve_consent",
                                      via: [ :get, :post ]

      post "verify_identity", to: "verifications#verify_identity"
      post "request_consent", to: "consents#create"

      # Per-Transaction Consent (financial partners)
      resources :transaction_consents, only: [ :create, :show ], param: :consent_token do
        member do
          post :decide
        end
      end
      get "bonid_status",    to: "bonid_status#show"
      get "public/bonid_lookup", to: "public_bonid_lookup#show"
      post "webhooks",        to: "webhooks#create"
      get  "/userinfo",       to: "userinfo#show"
      get  "/.well-known/openid-configuration", to: "discovery#show"
      post "qr_scan",         to: "qr_scans#create"
      get  "partner/metrics", to: "partners#metrics"

      # =========================================================================
      # Fiscal Receipt API (DGI ↔ Immigration anti-fraud)
      # =========================================================================
      resources :fiscal_receipts, only: [] do
        collection do
          get  :lookup   # GET  /api/v1/fiscal_receipts/lookup?receipt_number=...
          patch :consume # PATCH /api/v1/fiscal_receipts/consume
        end
      end
      post "oauth/token",     to: "partner_callbacks#exchange_token"
      post "oauth/revoke",    to: "partner_callbacks#revoke_token"

      resources :users, only: [ :show ] do
        member do
          get :bonid_profile
          get :verification_records
        end
      end

      # =========================================================================
      # Identity Verification API (for verified partners)
      # Supports both BonID (citizens) and BonTouris (tourists)
      # =========================================================================

      # Verify identity and get full details
      # GET /api/v1/identity/:bonid
      # Scopes required: identity:verify
      get "identity/:bonid", to: "identity#show", as: :identity_verify

      # Quick verification status check
      # GET /api/v1/identity/:bonid/status
      # Scopes required: identity:verify
      get "identity/:bonid/status", to: "identity#status", as: :identity_status

      # =========================================================================
      # Crime Status API (for verified partners: embassies, consulates, etc.)
      # Requires dual authentication: API key + OAuth token
      # =========================================================================

      # Check crime involvement status
      # GET /api/v1/crime_status/:bonid
      # Scopes required: crime:status
      get "crime_status/:bonid", to: "crime_status#show", as: :crime_status

      # Search incident reports by BonID
      # GET /api/v1/incident_reports?bonid=DV-1989-M-SE-P8697XDS
      # Scopes required: crime:reports
      resources :incident_reports, only: [ :index ] do
        member do
          # Get incident report certificate (JSON or PDF)
          # GET /api/v1/incident_reports/:id/certificate
          # Scopes required: crime:certificate
          get :certificate
        end
      end

      # =========================================================================
      # Election API — Diaspora Voting System
      # Authenticated endpoints for voter eligibility, vote casting, and
      # public ballot verification.
      # =========================================================================
      namespace :election do
        # Voter eligibility + vote casting
        get    ":election_id/eligibility",      to: "ballots#eligibility", as: :election_eligibility
        post   ":election_id/cast",             to: "ballots#cast",       as: :election_cast
        get    ":election_id/verify/:hash",     to: "ballots#verify",     as: :election_verify

        # Consulate kiosk management
        post   ":election_id/kiosk/register",   to: "kiosk#register",     as: :election_kiosk_register
        post   ":election_id/kiosk/scan",       to: "kiosk#scan",         as: :election_kiosk_scan
        get    ":election_id/kiosk/status",     to: "kiosk#status",       as: :election_kiosk_status
      end

      # =========================================================================
      # Certificate Verification API — PUBLIC (no auth required)
      # Used by embassies/consulates to verify a certificate they received
      # from a citizen without calling the main authenticated API.
      # =========================================================================

      # Verify a certificate signature cryptographically
      # POST /api/v1/certificates/verify
      # Body: { certificate_id, report_id, issued_at, partner_id, algorithm, signature_value }
      post "certificates/verify", to: "certificates#verify", as: :verify_certificate

      # Serve the RSA public key PEM for offline verification
      # GET /api/v1/certificates/public_key
      get "certificates/public_key", to: "certificates#public_key", as: :certificate_public_key

      # Ed25519 public key for BonID QR offline verification
      # GET /api/v1/public_keys/bonid
      get "public_keys/bonid", to: "public_keys#bonid", as: :bonid_public_key

      # Ed25519 public key for BonGouv receipt verification
      # GET /api/v1/public_keys/bongouv
      get "public_keys/bongouv", to: "public_keys#bongouv", as: :bongouv_public_key

      # Officer misconduct summary — for verified partners (embassies, consulates, law firms)
      # GET /api/v1/officers/:badge_id/complaints/summary
      # Requires: X-Partner-Api-Key + Bearer token with officer:complaints scope
      get "officers/:badge_id/complaints/summary",
          to: "officer_complaints#summary",
          as: :officer_complaints_summary
    end
  end

  # ===========================================================================
  # OAUTH FLOW (BonID Connect)
  # ===========================================================================
  resources :oauth, only: [] do
    collection do
      get  :authorize
      get  :consent
      post :decision
      post :token
      get  :userinfo
    end
  end

  # ===========================================================================
  # HIERARCHY LOOKUPS (Departments, Communes, etc.)
  # ===========================================================================
  get "/departments/:slug/arrondissements", to: "departments#arrondissements"
  get "/departments/:id/communes",          to: "departments#communes"  # Direct department → communes (skips arrondissement)
  get "/arrondissements/:id/communes",      to: "arrondissements#communes"
  get "/communes/:id/communal_sections",    to: "communes#communal_sections"
  get "/communal_sections/:id/postal_code", to: "communal_sections#postal_code"
  get "/communes", to: "communes#index"

  resources :banks, only: [] do
    collection { get :swift_lookup }
  end

  resources :emergency_contacts, only: [] do
    collection { get :fetch_from_bonid }
  end

  resources :schemas do
    member do
      get  :preview
      post :validate_sample
      post :preview_json
    end
  end

  namespace :partner_portal do
    resources :schemas do
      member do
        post :fork_template
        post :share_data
      end
    end
  end

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end


# Rails.application.routes.draw do
#   # ===========================================================================
#   # HEALTH & MONITORING
#   # ===========================================================================
#   get "/up", to: "rails/health#show", as: :rails_health_check

#   # ===========================================================================
#   # ROOT & PUBLIC PAGES
#   # ===========================================================================
#   root "main#home"

#   get "/start",      to: "main#start",      as: :start_verification
#   get "/partners",   to: "main#partners",   as: :partners
#   get "/pricing",    to: "main#pricing",    as: :pricing
#   get "/favicon.ico", to: redirect("/assets/favicon.ico")

#   # Static PDFs
#   get "/terms.pdf",    to: "pdfs#terms",   as: :terms_pdf
#   get "/privacy.pdf",  to: "pdfs#privacy", as: :privacy_pdf

#   # ===========================================================================
#   # PUBLIC API DOCS & VERSION
#   # ===========================================================================
#   get "/api/version",          to: "public_api#version"
#   get "/api/v1/openapi.yaml",  to: "public_api#pqopenapi"
#   get "/api/v1/openapi.json",  to: "public_api#openapi_json"

#   mount Rswag::Api::Engine => "/api/swagger"
#   mount Rswag::Ui::Engine  => "/swagger"
#   get  "/api-docs", to: redirect("/swagger")

#   # ===========================================================================
#   # PUBLIC VERIFICATION ENDPOINTS (No Auth Required)
#   # ===========================================================================
#   get  "/verify/:verification_token", to: "public/verifications#show", as: :public_verification
#   get  "verify/:public_token", to: "citizens/verifications#show", as: :verify_public_token

#   namespace :public do
#     resources :visitors, only: [ :new, :create ] do
#       collection { get :success }
#       member     { get :download_pdf }
#     end
#   end

#   # ===========================================================================
#   # DEVISE AUTHENTICATION (All Roles)
#   # ===========================================================================
#   devise_for :citizens,
#     class_name: "User",
#     path: "citizens",
#     controllers: {
#       sessions:      "citizens/sessions",
#       passwords:     "citizens/passwords",
#       registrations: "citizens/registrations"
#     }

#   devise_scope :citizen do
#     get   "citizens/otp_sign_in",      to: "citizens/sessions#otp_sign_in",      as: :citizens_otp_sign_in
#     post  "citizens/otp_sign_in",      to: "citizens/sessions#create_otp"
#     get   "citizens/verify_otp",       to: "citizens/sessions#verify_otp",       as: :citizens_verify_otp
#     post  "citizens/verify_otp",       to: "citizens/sessions#verify_otp"
#     post  "citizens/resend_otp",       to: "citizens/sessions#resend_otp",       as: :citizens_resend_otp
#   end

#   devise_for :officer,
#     class_name: "Officer",
#     path: "officers",
#     controllers: {
#       sessions:      "officers/sessions",
#       passwords:     "officers/passwords",
#       registrations: "officers/registrations",
#       invitations:   "officers/invitations",
#       confirmations: "officers/confirmations"
#     }

#   devise_scope :officer do
#     get "officers/invalid", to: redirect("/reviewer/sign_in")
#   end

#   devise_for :partner_admins,
#     class_name: "User",
#     path: "partner_admins",
#     controllers: {
#       sessions:   "partner_portal/partner_admins/sessions",
#       passwords:  "partner_portal/partner_admins/passwords",
#       invitations: "partner_portal/partner_admins/invitations"
#     },
#     skip: [ :registrations ]



#   devise_for :reviewers,
#     class_name: "User",
#     path: "reviewer",
#     controllers: {
#       sessions:  "reviewers/sessions",
#       passwords: "reviewers/passwords"
#     },
#     skip: [ :registrations ]

#   devise_for :admin_users,
#     class_name: "AdminUser",
#     path: "admin",
#     controllers: {
#       sessions: "admin/sessions",
#       passwords: "admin/passwords"
#     },
#     skip: [ :registrations ]

#   # ===========================================================================
#   # ADMIN NAMESPACE
#   # ===========================================================================
#   namespace :admin do
#     root to: "dashboards#index"
#     get  "dashboards/index", to: "dashboards#index", as: :dashboard

#     # Dashboard Exports
#     get "dashboards/export_users_csv",          to: "dashboards#export_users_csv"
#     get "dashboards/export_users_pdf",          to: "dashboards#export_users_pdf"
#     get "dashboards/export_officers_csv",       to: "dashboards#export_officers_csv"
#     get "dashboards/export_officers_pdf",       to: "dashboards#export_officers_pdf"
#     get "dashboards/export_partners_csv",       to: "dashboards#export_partners_csv"
#     get "dashboards/export_partners_pdf",       to: "dashboards#export_partners_pdf"
#     get "dashboards/export_verifications_csv",  to: "dashboards#export_verifications_csv"
#     get "dashboards/export_verifications_pdf",  to: "dashboards#export_verifications_pdf"

#     resources :partners do
#       member do
#         post :approve
#         post :reject
#         post :suspend
#         post :restore
#         post :soft_delete
#         post :rotate_api_key
#         post :regenerate_qr
#         post :resend_verification_email
#         get  :geocode_address
#       end
#       collection { get :invite_options }
#     end

#     resources :partner_plans do
#       member do
#         post :assign
#         get  :usage_report
#       end
#       collection { get :active }
#     end

#     resources :partner_schemas
#     resources :schemas, except: [ :show ] do
#       collection { get :select_partners }
#       member { post :assign_template }
#     end

#     resources :identity_submissions, only: [ :index, :show, :update ] do
#       member do
#         patch :approve
#         patch :reject
#         patch :approve_bin
#         patch :reject_bin
#         patch :approve_reset
#         patch :reject_reset
#         post  :regenerate_qr
#         post  :verify_signature
#       end
#       collection do
#         post  :bulk_update
#         post  :fallback_lookup
#         patch :bulk_approve_bin
#         patch :bulk_reject_bin
#       end
#     end

#     resources :incident_reports, only: [ :index, :show ] do
#       member do
#         post :approve
#         post :flag
#         get  :print
#         get  :download_pdf
#         get  :share
#       end
#     end

#     resources :reviewers, only: [ :index, :new, :create, :destroy ] do
#       collection do
#         get  :bulk_new
#         post :bulk_create
#       end
#     end

#     resources :officer_invitations, only: [ :new, :create ]
#     get  "officer_bulk_invitations/new", to: "officer_bulk_invitations#new", as: :new_officer_bulk_invitation
#     post "officer_bulk_invitations",     to: "officer_bulk_invitations#create", as: :officer_bulk_invitations

#     resources :qr_scan_logs, :partner_access_logs, :webhook_events, :oauth_events, :partner_audit_logs, only: [ :index, :show ]
#     resources :api_usage, only: [ :index ]
#     resources :qr_scans, only: [ :index ]

#     resources :guidelines, only: [ :index ] do
#       collection { post :confirm }
#     end
#   end

#   # ===========================================================================
#   # REVIEWERS NAMESPACE
#   # ===========================================================================
#   namespace :reviewers do
#     root to: "dashboard#index", as: :dashboard
#     get "dashboard", to: "dashboard#index"

#     resources :identity_submissions, only: %i[index show update] do
#       member do
#         patch :approve
#         patch :reject
#         patch :approve_bin
#         patch :reject_bin
#         patch :approve_reset
#         patch :reject_reset
#         post  :regenerate_qr
#         post  :verify_signature
#       end
#       collection do
#         post :bulk_update
#         post :fallback_lookup
#       end
#     end

#     resources :analytics,     only: [ :show ]
#     resources :audit_logs,    only: [ :index ]
#     resources :notifications, only: [ :index ]
#   end

#   # ===========================================================================
#   # CITIZENS / OFFICERS / PARTNER PORTAL (unchanged except fixes below)
#   # ===========================================================================
#   namespace :citizens do
#     root to: "dashboard#index"
#     get  "dashboard", to: "dashboard#index"

#     resource :profile, only: [ :new, :create, :show, :edit, :update ]
#     resources :verification_records
#     resources :addresses, only: [ :create ]
#     resources :consents, only: [ :index, :destroy ]

#     resources :identity_submissions, param: :public_token, only: [ :index, :new, :create, :show, :edit, :update ] do
#       collection do
#         post :request_new
#         get  :verify
#         get  :scan_history
#         get  :support_faq
#       end
#       member do
#         get  :verified_profile
#         post :refresh_qr
#       end
#     end
#   end

#   namespace :officers do
#     get "dashboard", to: "dashboard#index", as: :dashboard
#     get "dashboard/drafts", to: "dashboard#drafts", as: :dashboard_drafts
#     get "dashboard/crime_reports", to: "dashboard#crime_reports"
#     get "dashboard/recent_scans",  to: "dashboard#recent_scans"
#     get "dashboard/failed_scans",  to: "dashboard#failed_scans"
#     get "dashboard/:id", to: "dashboard#show", as: :dashboard_show

#     get "profile/edit", to: "profiles#edit", as: :edit_profile
#     patch "profile", to: "profiles#update", as: :profile

#     resources :border_entries, only: [ :index, :create ] do
#       member { patch :mark_exit }
#     end

#     resources :incident_reports do
#       collection do
#         get :bonid_lookup_manual
#         get :export_csv
#       end
#       member do
#         post :approve
#         post :flag
#         get  :print
#         get  :download_pdf
#         get  :share
#       end
#     end

#     resources :tickets
#     resources :bonid_lookups do
#       collection do
#         get :manual
#         get :failed
#       end
#     end
#     post "bonid_lookup", to: "bonid_lookups#create", as: :officers_bonid_lookup

#     get  "scan", to: "scans#new", as: :scan_qr_code
#     post "scan", to: "scans#create"
#     post "scan_qrcode", to: "scans#create_qrcode"
#     get "suspect_preview", to: "suspects#preview", as: :suspect_preview

#     resources :person_involvements, only: [] do
#       collection { get :fetch_identity }
#     end
#   end

#   namespace :partner_portal do
#     root to: redirect { |_p, req|
#       user = req.env["warden"].user(:partner_admin)
#       sector = user&.partner&.sector&.downcase
#       case sector
#       when "law_enforcement" then "/partner_portal/law_enforcement/dashboard"
#       when "banking", "financial_services", "fintech", "insurance" then "/partner_portal/banking/dashboard"
#       when "hospital", "healthcare" then "/partner_portal/hospital/dashboard"
#       when "embassy", "embassy_services" then "/partner_portal/embassy/dashboard"
#       else "/partner_portal/dashboard"
#       end
#     }

#     get "dashboard", to: "dashboard#index"
#     resources :access_logs, :settings, only: [ :index, :update ]
#     resource :metrics, only: [ :show ]

#     namespace :partner_admin do
#       resource :profile, only: [ :edit, :update ]
#     end

#     namespace :law_enforcement do
#       get "dashboard", to: "dashboard#index"
#       resources :officers
#       resources :incident_reports
#       resources :tickets
#     end

#     namespace :banking do
#       root to: redirect("/partner_portal/banking/dashboard")
#       get "dashboard", to: "dashboard#index", as: :dashboard

#       # FIXED: No more multi-path deprecation
#       get "api_docs",     to: ->(env) { [ 200, {}, [ "OK" ] ] }, as: :api_docs
#       get "api_keys",     to: ->(env) { [ 200, {}, [ "OK" ] ] }, as: :api_keys
#       get "reports",      to: ->(env) { [ 200, {}, [ "OK" ] ] }, as: :reports
#       get "customers",    to: ->(env) { [ 200, {}, [ "OK" ] ] }, as: :customers
#       get "transactions", to: ->(env) { [ 200, {}, [ "OK" ] ] }, as: :transactions
#       get "settings",     to: ->(env) { [ 200, {}, [ "OK" ] ] }, as: :settings
#       get "support",      to: ->(env) { [ 200, {}, [ "OK" ] ] }, as: :support

#       post "bonid_lookup", to: "verifications#lookup", as: :bonid_lookup
#       get  "kyc/new/:user_id", to: "kyc_requests#new", as: :new_kyc
#       get  "kyc", to: "kyc#index", as: :kyc

#       resources :agents, only: [ :new, :create, :index ] do
#         collection do
#           get  :invite_bulk
#           post :send_bulk_invite
#         end
#         member { post :resend_invite }
#       end
#       resources :teller_scans, only: [ :index ]
#     end

#     namespace :hospital do
#       get "dashboard", to: "dashboard#index"
#       resources :records, only: [ :show ] do
#         member { patch :verify }
#       end
#     end

#     namespace :embassy do
#       get "dashboard", to: "dashboard#index"
#       resources :partners, only: [ :index, :show ]
#       resources :api_keys, only: [ :index, :create, :destroy ] do
#         member { post :regenerate }
#       end
#     end
#   end

#       # ===========================================================================
#       # REST OF ROUTES (unchanged)
#       # ===========================================================================
#       # ==========================================================
#       # PARTNER EMAIL VERIFICATION ROUTES (MUST BE ROOT-LEVEL)
#       # ==========================================================
#       get "/partners/verify",
#       to: "partners/verifications#verify",
#       as: :partners_verify

#       get "/partners/verification/success",
#       to: "partners/verifications#success",
#       as: :partners_verification_success

#       get "/partners/verification/error",
#       to: "partners/verifications#error",
#       as: :partners_verification_error


#   resources :partners, only: [ :new, :create, :show ]

#   namespace :api do
#     namespace :v1 do
#       match "citizen/approve_consent", to: "citizen/consent_grants#approve_consent",
#             via: [ :get, :post ], as: :citizen_approve_consent

#       post "verify_identity", to: "verifications#verify_identity"
#       post "request_consent", to: "consents#create"
#       get  "bonid_status",    to: "bonid_status#show"
#       post "webhooks",        to: "webhooks#create"
#       get  "/userinfo",       to: "userinfo#show"
#       get  "/.well-known/openid-configuration", to: "discovery#show"
#       post "qr_scan",         to: "qr_scans#create"
#       get  "partner/metrics", to: "partners#metrics"
#       post "oauth/token",     to: "partner_callbacks#exchange_token"
#       post "oauth/revoke",    to: "partner_callbacks#revoke_token"

#       resources :users, only: [ :show ] do
#         member do
#           get :bonid_profile
#           get :verification_records
#         end
#       end
#     end
#   end

#   resources :oauth, only: [] do
#     collection do
#       get  :authorize
#       get  :consent
#       post :decision
#     end
#   end

#   get "/departments/:slug/arrondissements", to: "departments#arrondissements", as: :department_arrondissements
#   get "/arrondissements/:id/communes",      to: "arrondissements#communes",    as: :arrondissement_communes
#   get "/communes/:id/communal_sections",    to: "communes#communal_sections",  as: :commune_communal_sections
#   get "/communal_sections/:id/postal_code", to: "communal_sections#postal_code", as: :communal_section_postal_code
#   get "/communes", to: "communes#index"

#   resources :banks, only: [] do
#     collection { get :swift_lookup }
#   end

#   resources :emergency_contacts, only: [] do
#     collection { get :fetch_from_bonid }
#   end

#   resources :schemas do
#     member do
#       get  :preview
#       post :validate_sample
#       post :preview_json
#     end
#   end

#   namespace :partner_portal do
#     resources :schemas do
#       member do
#         post :fork_template
#         post :share_data
#       end
#     end
#   end

#   if Rails.env.development?
#     mount LetterOpenerWeb::Engine, at: "/letter_opener"
#   end
# end
# Rails.application.routes.draw do
# # ---------------------------------------------------------------------------
# # 📘 Public BonID API Specification & Version Routes
# # ---------------------------------------------------------------------------
# get "/api/v1/openapi.yaml", to: "public_api#openapi"
# get "/api/v1/openapi.json", to: "public_api#openapi_json"
# get "/api/version",          to: "public_api#version"

# # ---------------------------------------------------------------------------
# # 🌐 Public Verification (for partners, citizens, public viewers)
# # ---------------------------------------------------------------------------
# # Citizen-side verified view (requires login)
# get "verify/:public_token",
#     to: "citizens/verifications#show",
#     as: :verify_public_token

# # Public-facing verification (no login, public layout)
# get "/verify/:verification_token",
#     to: "public/verifications#show",
#     as: :public_verification


#   # ---------------------------------------------------------------------------
#   # 🔹 RSwag + Swagger UI
#   # ---------------------------------------------------------------------------
#   mount Rswag::Api::Engine => "/api/swagger"
#   mount Rswag::Ui::Engine  => "/swagger"
#   get "/api-docs", to: redirect("/swagger")

#   # === Root & Public Pages ===
#   root "main#home"

#   get "/start", to: "main#start", as: :start_verification
#   get "/partners", to: "main#partners", as: :partners
#   get "/favicon.ico", to: redirect("/assets/favicon.ico")
#   # get "/pricing", to: "partner_portal/plans#index", as: :pricing
#   get "/pricing", to: "main#pricing", as: :pricing


#   # post :approve
#   # post :reject
#   # post :suspend
#   # post :restore
#   # post :soft_delete
#   # post :rotate_api_key
#   # post :regenerate_qr
#   # post :resend_email




#   # ----------------------------------------------------------------------------
#   # Visitors to Haiti : QR Verification (read-only, no login required)
#   # ----------------------------------------------------------------------------
#   namespace :public do
#     resources :visitors, only: [ :new, :create ] do
#       collection do
#         get :success
#       end
#       member do
#         get :download_pdf
#       end
#     end
#   end


# # ----------------------------------------------------------------------------
# # PUBLIC: QR Verification (read-only, no login required)
# # ----------------------------------------------------------------------------
# scope module: :citizens do
#   resources :identity_submissions, param: :public_token, only: [] do
#     member do
#       get :verified_profile   # e.g. /identity_submissions/:public_token/verified_profile
#     end
#     collection do
#       get "verify/:token", to: "identity_submissions#verify", as: :verify  # e.g. /identity_submissions/verify/:token
#     end
#   end
# end

#   # ----------------------------------------------------------------------------
#   # Partner Price Plans
#   # ----------------------------------------------------------------------------
#   namespace :partner_portal do
#     resources :plans, only: [ :index, :show ] do
#       member do
#         get :upgrade  # Show upgrade form/checkout
#         post :checkout  # Create Stripe session
#       end
#     end
#   end


#   # ----------------------------------------------------------------------------
#   # BONID AUTH ROUTES (Unified for all Devise Roles)
#   # ----------------------------------------------------------------------------
#   devise_for :citizens,
#     class_name: "User",
#     path: "citizens",
#     controllers: {
#       sessions: "citizens/sessions",
#       passwords: "citizens/passwords",
#       registrations: "citizens/registrations"
#     }

#   # --------------------------------------------------------
#   # Citizen OTP Login Flow
#   # --------------------------------------------------------
#   devise_scope :citizen do
#     get "citizens/otp_sign_in", to: "citizens/sessions#otp_sign_in", as: :citizens_otp_sign_in
#     post "citizens/otp_sign_in", to: "citizens/sessions#create_otp"
#     get "citizens/verify_otp", to: "citizens/sessions#verify_otp", as: :citizens_verify_otp
#     post "citizens/verify_otp", to: "citizens/sessions#verify_otp"
#     post "citizens/resend_otp", to: "citizens/sessions#resend_otp", as: :citizens_resend_otp
#   end

#   # Officers (Law Enforcement Portal)
#   devise_for :officer,
#              class_name: "Officer",
#              path: "officers",
#              controllers: {
#                sessions: "officers/sessions",
#                passwords: "officers/passwords",
#                registrations: "officers/registrations",
#                invitations: "officers/invitations",
#                confirmations: "officers/confirmations"
#              }


#       # Partner Admins (Institutional Logins)
#       devise_for :partner_admins,
#       class_name: "User",
#             path: "partner_admins",
#             controllers: {
#               sessions: "partner_portal/partner_admins/sessions",
#               passwords: "partner_portal/partner_admins/passwords",
#               invitations: "partner_portal/partner_admins/invitations"
#             },
#       skip: [ :registrations ]

#       namespace :partner_portal do
#         namespace :partner_admins do
#           get "dashboard", to: "dashboard#index", as: :dashboard

#           resources :partners, only: [ :new, :create ]
#           resource :profile, only: [ :edit, :update ]
#         end
#       end


# # === Banking Agents / Tellers ===
# # === Banking Agents / Tellers ===
# devise_for :banking_agents,
#   class_name: "BankingAgent",
#   path: "banking_agents",
#   controllers: {
#     sessions: "partner_portal/banking_agents/sessions",
#     passwords: "partner_portal/banking_agents/passwords",
#     registrations: "partner_portal/banking_agents/registrations",
#     invitations: "partner_portal/banking_agents/invitations",
#     confirmations: "partner_portal/banking_agents/confirmations"
#   }

# namespace :partner_portal do
#   namespace :banking_agents do
#     get "dashboard", to: "dashboard#index", as: :dashboard
#   end
# end


#       # Admin (System Admin Panel)
#       # === System Admin (ActiveAdmin + Devise) ===

#       devise_for :admin_users,
#       class_name: "AdminUser",
#       path: "admin",
#       controllers: {
#         sessions: "admin/sessions",
#         passwords: "admin/passwords"
#       },
#       skip: [ :registrations ]


#       namespace :admin do
#         # Admin root
#         root to: "dashboards#index"

#         # Dashboard main page
#         get "dashboards/index", to: "dashboards#index", as: :dashboard

#         # === Dashboard Export Routes ===
#         get "dashboards/export_users_csv",          to: "dashboards#export_users_csv"
#         get "dashboards/export_users_pdf",          to: "dashboards#export_users_pdf"

#         get "dashboards/export_officers_csv",       to: "dashboards#export_officers_csv"
#         get "dashboards/export_officers_pdf",       to: "dashboards#export_officers_pdf"

#         get "dashboards/export_partners_csv",       to: "dashboards#export_partners_csv"
#         get "dashboards/export_partners_pdf",       to: "dashboards#export_partners_pdf"

#         get "dashboards/export_verifications_csv",  to: "dashboards#export_verifications_csv"
#         get "dashboards/export_verifications_pdf",  to: "dashboards#export_verifications_pdf"
#       end




#   # Reviewers (role-based auth for reviewers)
#   devise_for :reviewers,
#     class_name: "User",
#     path: "reviewer",
#     controllers: {
#       sessions: "reviewers/sessions",
#       passwords: "reviewers/passwords"
#     },
#     skip: [ :registrations ]

#   # If you need custom routes for dashboard, add:
#   namespace :reviewer do
#     get "dashboard", to: "dashboard#index", as: :dashboard
#   end


# # ----------------------------------------------------------------------------
# # Citizens namespace
# # ----------------------------------------------------------------------------
# namespace :citizens do
#   root to: "dashboard#index"
#   get "dashboard", to: "dashboard#index"
#   resource :profile, only: %i[new create show edit update]

#   # ✅ Add full RESTful routes for identity submissions
#   resources :identity_submissions, param: :public_token, only: %i[index new create show edit update] do
#     collection do
#       post :request_new
#       get :verify
#       get :scan_history
#       get :support_faq
#     end
#     member do
#       get :verified_profile
#       post :refresh_qr
#     end
#   end

#   resources :verification_records
#   resources :addresses, only: [ :create ]
#   resources :consents, only: [ :index, :destroy ]
# end


#   # ----------------------------------------------------------------------------
#   # Partners (Merged from PartnerApplication)
#   # ----------------------------------------------------------------------------
#   namespace :partners do
#     get "verify", to: "verifications#verify", as: :verify
#     get "verification/success", to: "verifications#success", as: :verification_success
#     get "verification/error",   to: "verifications#error",   as: :verification_error
#   end


#   resources :partners, only: %i[new create show]

#   namespace :partner_portal do
#     resources :schemas
#   end

#   namespace :admin do
#     resources :partners, only: [ :index, :show, :edit, :update, :destroy ] do
#       member do
#         post :approve
#         post :reject
#         get :geocode_address
#       end
#     end

#   # NEW: API Plans Management (CRUD for admins)
#   resources :partner_plans do
#     member do
#       post :assign  # Assign to partner
#       get :usage_report  # Optional: View partner usage
#     end
#     collection do
#       get :active  # List active plans
#     end
#   end

#     resources :partner_schemas do
#       member do
#         patch :approve
#         patch :reject
#         patch :deactivate
#       end
#     end
#   end

#   # Emergency contacts
#   resources :emergency_contacts, only: [] do
#     collection { get :fetch_from_bonid }
#   end

#   # ----------------------------------------------------------------------------
#   # ADMIN NAMESPACE
#   # ----------------------------------------------------------------------------

#   namespace :admin do
#     # root to: "dashboards#index"
#     # get "dashboards/index"
#     resources :partner_audit_logs, only: [ :index ]
#     resources :reviewers, only: [ :index, :new, :create, :destroy ]
#     resources :partners do
#       get "dashboard", to: "partners#dashboard", as: :partner_dashboard
#       post "invite_officer", to: "partners#invite_officer", as: :invite_officer

#       resources :partner_admin_invitations, only: %i[new create] do
#         get :option_invites, on: :collection
#       end
#       resources :partner_reviewer_invitations, only: %i[new create]
#       resources :officers, only: %i[index new create show edit update]
#       resources :assignments, only: %i[index new create edit update]

#       member do
#         post :resend_verification_email
#         get :invite_options
#         get :invite_single
#         post :send_invite_single
#         get :invite_bulk
#         post :send_invite_bulk
#       end

#     # ================================
#     # FULL ADMIN PARTNER ACTIONS
#     # ================================
#     member do
#       post :approve
#       post :reject
#       post :suspend
#       post :restore
#       post :soft_delete
#       post :rotate_api_key
#       post :regenerate_qr
#       post :resend_verification_email
#     end
#     end

#     resources :guidelines, only: [ :index ] do
#       post :confirm, on: :collection
#     end

#     resources :incident_reports, only: %i[index show] do
#       member do
#         post :approve
#         post :flag
#         get :print
#         get :download_pdf
#         get :share
#       end
#     end

#     resources :officer_invitations, only: %i[new create]
#     get "officer_bulk_invitations/new", to: "officer_bulk_invitations#new", as: :new_officer_bulk_invitation
#     post "officer_bulk_invitations", to: "officer_bulk_invitations#create", as: :officer_bulk_invitations

#     resources :identity_submissions, only: %i[index show update] do
#       member do
#         patch :approve
#         patch :reject
#         patch :approve_bin
#         patch :reject_bin
#         patch :approve_reset
#         patch :reject_reset
#         post :regenerate_qr
#         post :verify_signature
#       end
#       collection do
#         post :bulk_update
#         patch :approve_bin, to: "identity_submissions#bulk_approve_bin"
#         patch :reject_bin, to: "identity_submissions#bulk_reject_bin"
#         post :fallback_lookup
#       end
#     end

#     resources :qr_scans, only: [ :index ]
#     resources :qr_scan_logs, only: [ :index ]
#     resources :partner_access_logs, only: [ :index ]
#     resources :webhook_events, only: [ :index, :show ]

#     # --------------------------------------------------------------------------
#     # OAuth Events
#     # --------------------------------------------------------------------------
#     resources :oauth_events, only: [ :index, :show ] do
#       member do
#         post :replay
#       end
#     end

#     # --------------------------------------------------------------------------
#     # Partner API Usage (correct, non-nested)
#     # --------------------------------------------------------------------------
#     resources :api_usage, only: [ :index ]
#   end

#   # -------------------------------------------------------------
#   # REVIEWERS
#   # –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––-

#   namespace :reviewers do
#     resources :identity_submissions, only: [ :index, :show ] do
#       member do
#         patch :approve
#         patch :reject
#         patch :regenerate_qr
#       end
#     end
#   end



# # ----------------------------------------------------------------------------
# # OFFICERS
# # ----------------------------------------------------------------------------

# devise_scope :officer do
#   get "officers/invalid", to: redirect("/reviewer/sign_in")
# end

# namespace :officers do
#   # --- Dashboard ---
#   get "dashboard", to: "dashboard#index", as: :dashboard
#   get "dashboard/drafts", to: "dashboard#drafts", as: :dashboard_drafts
#   get "dashboard/crime_reports", to: "dashboard#crime_reports"
#   get "dashboard/recent_scans", to: "dashboard#recent_scans"
#   get "dashboard/failed_scans", to: "dashboard#failed_scans"
#   get "dashboard/:id", to: "dashboard#show", as: :dashboard_show

#   # --- Profile ---
#   get "profile/edit", to: "profiles#edit", as: :edit_profile
#   patch "profile", to: "profiles#update", as: :profile

#   # --- Border Entries (Visitor BonID) ---
#   resources :border_entries, only: [ :index, :create ] do
#     member do
#       patch :mark_exit
#     end
#   end

#   # --- Person Involvements ---
#   resources :person_involvements, only: [] do
#     get :fetch_identity, on: :collection
#   end

#   # --- Incident Reports ---
#   resources :incident_reports do
#     collection do
#       get :bonid_lookup_manual
#       get :export_csv
#     end
#     member do
#       post :approve
#       post :flag
#       get :print
#       get :download_pdf
#       get :share
#     end
#   end

#   # --- Tickets ---
#   resources :tickets

#   # --- BonID Lookups ---
#   resources :bonid_lookups do
#     collection do
#       get :manual
#       get :failed
#     end
#   end
#   post "bonid_lookup", to: "bonid_lookups#create", as: :officers_bonid_lookup

#   # --- QR Scan Routes ---
#   get "scan", to: "scans#new", as: :scan_qr_code
#   post "scan", to: "scans#create"
#   post "scan_qrcode", to: "scans#create_qrcode"

#   # --- Suspect Preview ---
#   get "suspect_preview", to: "suspects#preview", as: :suspect_preview
# end


#   # ----------------------------------------------------------------------------
#   # PARTNER PORTAL (All Sectors)
#   # ----------------------------------------------------------------------------
#   namespace :partner_portal do
#     root to: redirect { |_params, req|
#       user = req.env["warden"].user(:partner_admin)
#       sector = user&.partner&.sector&.downcase

#       case sector
#       when "law_enforcement" then "/partner_portal/law_enforcement/dashboard"
#       when "banking", "financial_services", "fintech", "insurance" then "/partner_portal/banking/dashboard"
#       when "hospital", "healthcare" then "/partner_portal/hospital/dashboard"
#       when "embassy", "embassy_services" then "/partner_portal/embassy/dashboard"
#       else "/partner_portal/dashboard"
#       end
#     }

#     get "dashboard", to: "dashboard#index"
#     resources :access_logs, only: [ :index ]
#     resources :settings, only: [ :index, :update ]
#     resources :metrics, only: [ :show ], controller: "metrics"

#     namespace :partner_admin do
#       resource :profile, only: [ :edit, :update ]
#     end

#     namespace :law_enforcement do
#       get "dashboard", to: "dashboard#index"
#       resources :officers
#       resources :incident_reports
#       resources :tickets
#     end

#     namespace :banking do
#       root to: redirect("/partner_portal/banking/dashboard")
#       get "dashboard", to: "dashboard#index", as: :dashboard
#       get "api_docs", to: "api_docs#index", as: :api_docs
#       get "api_keys", to: "api_keys#index", as: :api_keys
#       get "reports", to: "reports#index", as: :reports
#       get "customers", to: "customers#index", as: :customers
#       get "transactions", to: "transactions#index", as: :transactions
#       get "settings", to: "settings#index", as: :settings
#       get "support", to: "support#index", as: :support

#       post "bonid_lookup", to: "verifications#lookup", as: :bonid_lookup
#       get "kyc/new/:user_id", to: "kyc_requests#new", as: :new_kyc
#       get "kyc", to: "kyc#index", as: :kyc

#       resources :agents, only: [ :new, :create, :index ] do
#         collection do
#           get :invite_bulk
#           post :send_bulk_invite
#         end
#         member do
#           post :resend_invite
#         end
#         resources :kyc_requests, only: [ :new ] do
#           post :verify, on: :member
#           post :flag, on: :member
#         end
#       end

#       resources :partners, only: [ :index, :show ]
#       resources :teller_scans, only: [ :index ]
#     end

#     namespace :hospital do
#       get "dashboard", to: "dashboard#index"
#       resources :records, only: [ :show ] do
#         patch :verify, on: :member
#       end
#     end

#     namespace :embassy do
#       get "dashboard", to: "dashboard#index"
#       resources :partners, only: [ :index, :show ]

#       resources :api_keys, only: [ :index, :create, :destroy ] do
#         member do
#           post :regenerate
#         end
#       end
#     end

#     resources :partners, only: [] do
#       member do
#         get :dashboard
#         get :invite_options
#         get :invite_single
#         post :send_invite_single
#         get :invite_bulk
#         post :send_invite_bulk
#       end
#     end

#     resources :officer_invitations, only: [ :new, :create, :destroy ] do
#       collection do
#         get :bulk_new
#         post :bulk_create
#       end
#       member { post :resend }
#     end

#     resources :bonid_lookups, only: [ :index, :show, :create ] do
#       collection do
#         get :manual
#         get :failed
#       end
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # BANKS Ready API
#   # ----------------------------------------------------------------------------
#   resources :banks, only: [] do
#     collection { get :swift_lookup }
#   end

#   # ----------------------------------------------------------------------------
#   # SHARED UTILITIES
#   # ----------------------------------------------------------------------------
#   get "/departments/:slug/arrondissements", to: "departments#arrondissements", as: :department_arrondissements
#   get "/arrondissements/:id/communes", to: "arrondissements#communes", as: :arrondissement_communes
#   get "/communes/:id/communal_sections", to: "communes#communal_sections", as: :commune_communal_sections
#   get "/communal_sections/:id/postal_code", to: "communal_sections#postal_code", as: :communal_section_postal_code
#   get "/communes", to: "communes#index"

#   get "/terms.pdf", to: "pdfs#terms", as: :terms_pdf
#   get "/privacy.pdf", to: "pdfs#privacy", as: :privacy_pdf

#   get "/up", to: "rails/health#show", as: :rails_health_check

#   # ----------------------------------------------------------------------------
#   # BonID Partner API (v1) — RSwag Driven
#   # ----------------------------------------------------------------------------
#   # ==========================
#   # OAuth2 Authorization Flow
#   # ==========================
#   resources :oauth, only: [] do
#     collection do
#       get :authorize
#       get :consent
#       post :decision
#     end
#   end

#   # ==========================
#   # API v1 (Public + Partner)
#   # ==========================
#   namespace :api do
#     namespace :v1 do
#       # Citizens → Consent Grants API (Approve / Reject from email)
#       match "citizen/approve_consent",
#       to: "citizen/consent_grants#approve_consent",
#       via: [ :get, :post ],
#       as: :citizen_approve_consent


#       post "verify_identity", to: "verifications#verify_identity"
#       post "request_consent", to: "consents#create"
#       get "bonid_status", to: "bonid_status#show"
#       post "webhooks", to: "webhooks#create"
#       get  "/userinfo", to: "userinfo#show"
#       get  "/.well-known/openid-configuration", to: "discovery#show"
#       post "qr_scan", to: "qr_scans#create"
#       get "partner/metrics", to: "partners#metrics"

#       post "oauth/token", to: "partner_callbacks#exchange_token"
#       post "oauth/revoke", to: "partner_callbacks#revoke_token"

#       resources :users, only: [ :show ] do
#         member do
#           get :bonid_profile
#           get :verification_records
#         end
#       end
#     end
#   end

# # ----------------------------------------------------------------------------
# # Schema Tools (Partner Integrations)
# # ----------------------------------------------------------------------------
# # ----------------------------------------------------------------------------
# # Schema Tools (Partner Integrations)
# # ----------------------------------------------------------------------------
# resources :schemas do
#   member do
#     get :preview
#     post :validate_sample
#     post :preview_json
#   end
# end

# namespace :partner_portal do
#   resources :schemas do
#     member do
#       post :fork_template  # Partners fork admin templates
#       post :share_data  # Share schema data with other partners/banks
#     end
#   end
# end

# namespace :admin do
#   resources :schemas, only: [ :index, :new, :create, :edit, :update, :destroy ] do
#     member do
#       post :assign_template  # Assign template to specific partner
#     end
#     collection do
#       get :select_partners  # List verified partners by sector
#     end
#   end

#   resources :partner_schemas, only: [ :index, :show ] do
#     member do
#       patch :approve
#       patch :reject
#       patch :deactivate
#     end
#   end
# end
#   # ----------------------------------------------------------------------------
#   # DEV UTILITIES
#   # ----------------------------------------------------------------------------
#   if Rails.env.development?
#     mount LetterOpenerWeb::Engine, at: "/letter_opener"
#   end
# end

# # frozen_string_literal: true

# Rails.application.routes.draw do
#   namespace :admin do
#     get "api_usage/index"
#   end

#   # ---------------------------------------------------------------------------
#   # 🔹 RSwag API + Swagger UI Integration
#   # ---------------------------------------------------------------------------
#   mount Rswag::Api::Engine => "/api/swagger"
#   mount Rswag::Ui::Engine => "/swagger"
#   get "/api-docs", to: redirect("/swagger")

#   # === Root & Public Pages ===
#   root "main#home"

#   get "/start", to: "main#start", as: :start_verification
#   get "/partners", to: "main#partners", as: :partners
#   get "/partners/verify/:slug", to: "partners#verify", as: :partners_verification
#   get "/favicon.ico", to: redirect("/assets/favicon.ico")
#   get "/pricing", to: "partner_portal/plans#index", as: :pricing

#   # ----------------------------------------------------------------------------
#   # PUBLIC + CITIZEN IDENTITY SUBMISSIONS (non-guessable public_token routes)
#   # ----------------------------------------------------------------------------
#   resources :identity_submissions, param: :public_token do
#     member do
#       get :verified_profile
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # Partner Price Plans
#   # ----------------------------------------------------------------------------
#   namespace :partner_portal do
#     resources :plans, only: [ :index ] do
#       member { get :checkout }
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # PUBLIC: QR Verification (read-only, no login required)
#   # ----------------------------------------------------------------------------
#   resources :identity_submissions, only: [], param: :public_token do
#     member { get :verified_profile }
#     collection { get "verify/:token", to: "identity_submissions#verify", as: :verify }
#   end

#   # ----------------------------------------------------------------------------
#   # BONID AUTH ROUTES (Unified for all Devise Roles)
#   # ----------------------------------------------------------------------------
#   devise_for :citizens,
#     class_name: "User",
#     path: "citizens",
#     controllers: {
#       sessions: "citizens/sessions",
#       passwords: "citizens/passwords",
#       registrations: "citizens/registrations"
#     }

#   # --------------------------------------------------------
#   # Citizen OTP Login Flow
#   # --------------------------------------------------------
#   devise_scope :citizen do
#     get "citizens/otp_sign_in", to: "citizens/sessions#otp_sign_in", as: :citizens_otp_sign_in
#     post "citizens/otp_sign_in", to: "citizens/sessions#create_otp"
#     get "citizens/verify_otp", to: "citizens/sessions#verify_otp", as: :citizens_verify_otp
#     post "citizens/verify_otp", to: "citizens/sessions#verify_otp"
#     post "citizens/resend_otp", to: "citizens/sessions#resend_otp", as: :citizens_resend_otp
#   end

#   # Officers (Law Enforcement Portal)
#   devise_for :officers,
#     class_name: "User",
#     path: "officers",
#     controllers: {
#       sessions: "officers/sessions",
#       passwords: "officers/passwords",
#       invitations: "officers/invitations"
#     }

#   # Partner Admins (Institutional Logins)
#   devise_for :partner_admins,
#     class_name: "User",
#     path: "partner_admin",
#     controllers: {
#       sessions: "partner_portal/partner_admin/sessions",
#       passwords: "partner_portal/partner_admin/passwords",
#       invitations: "partner_portal/partner_admin/invitations",
#       registrations: "devise_invitable/registrations"
#     }

#   # Banking Agents
#   devise_for :banking_agents,
#     class_name: "BankingAgent",
#     path: "banking_agents",
#     controllers: {
#       sessions: "partner_portal/banking_agents/sessions",
#       passwords: "partner_portal/banking_agents/passwords",
#       invitations: "partner_portal/banking_agents/invitations",
#       registrations: "partner_portal/banking_agents/registrations"
#     }

#   # Admin (System Admin Panel)
#   devise_for :admin_users,
#     class_name: "AdminUser",
#     path: "admin",
#     controllers: {
#       sessions: "admin/sessions",
#       passwords: "admin/passwords"
#     },
#     skip: [ :registrations ]

#     # Reviewers
#     # Reviewers (role-based auth for reviewers)
#     devise_for :reviewers,
#         class_name: "User",
#         path: "reviewer",
#         controllers: {
#           sessions: "reviewers/sessions",  # FIXED: 'reviewers' plural for namespace
#           passwords: "reviewers/passwords"
#         },
#         skip: [ :registrations ]

#         # If you need custom routes for dashboard, add:
#         namespace :reviewer do
#         get "dashboard", to: "dashboard#index", as: :dashboard
#     end
#   # ----------------------------------------------------------------------------
#   # Citizens namespace
#   # ----------------------------------------------------------------------------
#   namespace :citizens do
#     resource :profile, only: %i[new create show edit update]
#     resources :identity_submissions, param: :public_token do
#       collection do
#         post :request_new
#         get :verify
#         get :scan_history
#         get :support_faq
#       end
#       member do
#         post :request_new
#         post :refresh_qr
#       end
#     end

#     resources :verification_records
#     resources :addresses, only: [ :create ]
#     resources :consents, only: [ :index, :create, :destroy ]
#   end

# # ----------------------------------------------------------------------------
# # Partners (Merged from PartnerApplication)
# # ----------------------------------------------------------------------------

# namespace :partner_portal do
#   resources :schemas
# end


# namespace :admin do
#   resources :partners, only: [ :index, :show, :edit, :update, :destroy ] do  # FIXED: Added full CRUD for admin management
#     member do
#       post :approve  # FIXED: POST for approve/reject (from your controller)
#       post :reject
#       get :geocode_address
#     end
#   end

#   resources :partner_schemas do
#     member do
#       patch :approve
#       patch :reject
#       patch :deactivate
#     end
#   end
# end

#   # Emergency contacts
#   resources :emergency_contacts, only: [] do
#     collection { get :fetch_from_bonid }
#   end

#   # ----------------------------------------------------------------------------
#   # ADMIN NAMESPACE
#   # ----------------------------------------------------------------------------

#   namespace :admin do
#     root to: "dashboards#index"
#     get "dashboards/index"

#     resources :partners do
#       get "dashboard", to: "partners#dashboard", as: :partner_dashboard
#       post "invite_officer", to: "partners#invite_officer", as: :invite_officer

#       resources :partner_admin_invitations, only: %i[new create] do
#         get :option_invites, on: :collection
#       end
#       resources :partner_reviewer_invitations, only: %i[new create]
#       resources :officers, only: %i[index new create show edit update]
#       resources :assignments, only: %i[index new create edit update]

#       member do
#         post :resend_verification_email
#         get :invite_options
#         get :invite_single
#         post :send_invite_single
#         get :invite_bulk
#         post :send_invite_bulk
#       end
#     end

#     resources :guidelines, only: [ :index ] do
#       post :confirm, on: :collection
#     end

#       post :geocode_address, on: :member
#     end

#     resources :incident_reports, only: %i[index show] do
#       member do
#         post :approve
#         post :flag
#         get :print
#         get :download_pdf
#         get :share
#       end
#     end

#     resources :officer_invitations, only: %i[new create]
#     get "officer_bulk_invitations/new", to: "officer_bulk_invitations#new", as: :new_officer_bulk_invitation
#     post "officer_bulk_invitations", to: "officer_bulk_invitations#create", as: :officer_bulk_invitations

#     resources :identity_submissions, param: :public_token do
#       member do
#         patch :approve
#         patch :reject
#         patch :approve_bin
#         patch :reject_bin
#         patch :approve_reset
#         patch :reject_reset
#         post :regenerate_qr
#         post :verify_signature
#       end
#       collection do
#         post :bulk_update
#         patch :approve_bin, to: "identity_submissions#bulk_approve_bin"
#         patch :reject_bin, to: "identity_submissions#bulk_reject_bin"
#         post :fallback_lookup
#       end
#     end

#     resources :qr_scans, only: [ :index ]
#     resources :qr_scan_logs, only: [ :index ]
#     resources :partner_access_logs, only: [ :index ]
#     resources :webhook_events, only: [ :index, :show ]

#     # --------------------------------------------------------------------------
#     # OAuth Events
#     # --------------------------------------------------------------------------
#     resources :oauth_events, only: [ :index, :show ] do
#       member do
#         post :replay
#       end
#     end

#     # --------------------------------------------------------------------------
#     # Partner API Usage (correct, non-nested)
#     # --------------------------------------------------------------------------
#     resources :api_usage, only: [ :index ]
#   end

#   # -------------------------------------------------------------
#   # REVIEWERS
#   # –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––-

#   namespace :reviewers do
#     resources :identity_submissions, only: [ :index, :show ] do
#       member do
#         patch :approve
#         patch :reject
#         patch :regenerate_qr
#       end
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # OFFICERS
#   # ----------------------------------------------------------------------------
#   devise_scope :officer do
#     get "officers/invalid", to: redirect("/reviewer/sign_in")
#   end

#   namespace :officers do
#     get "dashboard", to: "dashboard#index", as: :dashboard
#     get "dashboard/drafts", to: "dashboard#drafts", as: :dashboard_drafts
#     get "dashboard/crime_reports", to: "dashboard#crime_reports"
#     get "dashboard/recent_scans", to: "dashboard#recent_scans"
#     get "dashboard/failed_scans", to: "dashboard#failed_scans"
#     get "dashboard/:id", to: "dashboard#show", as: :dashboard_show

#     get "profile/edit", to: "profiles#edit", as: :edit_profile
#     patch "profile", to: "profiles#update", as: :profile

#     resources :person_involvements, only: [] do
#       get :fetch_identity, on: :collection
#     end

#     resources :incident_reports do
#       collection do
#         get :bonid_lookup_manual
#         get :export_csv
#       end
#       member do
#         post :approve
#         post :flag
#         get :print
#         get :download_pdf
#         get :share
#       end
#     end

#     resources :tickets
#     resources :bonid_lookups do
#       collection do
#         get :manual
#         get :failed
#       end
#     end
#     post "bonid_lookup", to: "bonid_lookups#create", as: :officers_bonid_lookup

#     get "scan", to: "scans#new", as: :scan_qr_code
#     post "scan", to: "scans#create"
#     post "scan_qrcode", to: "scans#create_qrcode"

#     get "suspect_preview", to: "suspects#preview", as: :suspect_preview
#   end

#   # ----------------------------------------------------------------------------
#   # PARTNER PORTAL (All Sectors)
#   # ----------------------------------------------------------------------------
#   namespace :partner_portal do
#     root to: redirect { |_params, req|
#       user = req.env["warden"].user(:partner_admin)
#       sector = user&.partner&.sector&.downcase

#       case sector
#       when "law_enforcement" then "/partner_portal/law_enforcement/dashboard"
#       when "banking", "financial_services", "fintech", "insurance" then "/partner_portal/banking/dashboard"
#       when "hospital", "healthcare" then "/partner_portal/hospital/dashboard"
#       when "embassy", "embassy_services" then "/partner_portal/embassy/dashboard"
#       else "/partner_portal/dashboard"
#       end
#     }

#     get "dashboard", to: "dashboard#index"
#     resources :access_logs, only: [ :index ]

#     resource :metrics, only: [ :show ], controller: "metrics"

#     namespace :partner_admin do
#       resource :profile, only: [ :edit, :update ]
#     end

#     namespace :law_enforcement do
#       get "dashboard", to: "dashboard#index"
#       resources :officers
#       resources :incident_reports
#       resources :tickets
#     end

#     namespace :banking do
#       root to: redirect("/partner_portal/banking/dashboard")
#       get "dashboard", to: "dashboard#index", as: :dashboard
#       get "api_docs", to: "api_docs#index", as: :api_docs
#       get "api_keys", to: "api_keys#index", as: :api_keys
#       get "reports", to: "reports#index", as: :reports
#       get "customers", to: "customers#index", as: :customers
#       get "transactions", to: "transactions#index", as: :transactions
#       get "settings", to: "settings#index", as: :settings
#       get "support", to: "support#index", as: :support

#       post "bonid_lookup", to: "verifications#lookup", as: :bonid_lookup
#       get "kyc/new/:user_id", to: "kyc_requests#new", as: :new_kyc
#       get "kyc", to: "kyc#index", as: :kyc

#       resources :agents, only: [ :new, :create, :index ] do
#         collection do
#           get :invite_bulk
#           post :send_bulk_invite
#         end
#         member do
#           post :resend_invite
#         end
#         resources :kyc_requests, only: [ :new ] do
#           post :verify, on: :member
#           post :flag, on: :member
#         end
#       end

#       resources :partners, only: [ :index, :show ]
#       resources :teller_scans, only: [ :index ]
#     end

#     namespace :hospital do
#       get "dashboard", to: "dashboard#index"
#       resources :records, only: [ :show ] do
#         patch :verify, on: :member
#       end
#     end

#     namespace :embassy do
#       get "dashboard", to: "dashboard#index"
#       resources :partners, only: [ :index, :show ]

#       resources :api_keys, only: [ :index, :create, :destroy ] do
#         member do
#           post :regenerate
#         end
#       end
#     end

#     resources :partners, only: [] do
#       member do
#         get :dashboard
#         get :invite_options
#         get :invite_single
#         post :send_invite_single
#         get :invite_bulk
#         post :send_invite_bulk
#       end
#     end

#     resources :officer_invitations, only: [ :new, :create, :destroy ] do
#       collection do
#         get :bulk_new
#         post :bulk_create
#       end
#       member { post :resend }
#     end

#     resources :bonid_lookups, only: [ :index, :show, :create ] do
#       collection do
#         get :manual
#         get :failed
#       end
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # BANKS Ready API
#   # ----------------------------------------------------------------------------
#   resources :banks, only: [] do
#     collection { get :swift_lookup }
#   end

#   # ----------------------------------------------------------------------------
#   # SHARED UTILITIES
#   # ----------------------------------------------------------------------------
#   get "/departments/:slug/arrondissements", to: "departments#arrondissements", as: :department_arrondissements
#   get "/arrondissements/:id/communes", to: "arrondissements#communes", as: :arrondissement_communes
#   get "/communes/:id/communal_sections", to: "communes#communal_sections", as: :commune_communal_sections
#   get "/communal_sections/:id/postal_code", to: "communal_sections#postal_code", as: :communal_section_postal_code
#   get "/communes", to: "communes#index"

#   get "/terms.pdf", to: "pdfs#terms", as: :terms_pdf
#   get "/privacy.pdf", to: "pdfs#privacy", as: :privacy_pdf

#   get "/up", to: "rails/health#show", as: :rails_health_check

#   # ----------------------------------------------------------------------------
#   # BonID Partner API (v1) — RSwag Driven
#   # ----------------------------------------------------------------------------
#   # ==========================
#   # OAuth2 Authorization Flow
#   # ==========================
#   resources :oauth, only: [] do
#     collection do
#       get :authorize
#       get :consent
#       post :decision
#     end
#   end

#   # ==========================
#   # API v1 (Public + Partner)
#   # ==========================
#   namespace :api do
#     namespace :v1 do
#       match "citizen/approve_consent", to: "citizen_consents#approve", via: [ :get, :post ], as: :citizen_approve_consent

#       post "verify_identity", to: "verifications#verify_identity"
#       post "request_consent", to: "consents#create"
#       get "bonid_status", to: "bonid_status#show"
#       post "webhooks", to: "webhooks#create"
#       post "qr_scan", to: "qr_scans#create"
#       get "partner/metrics", to: "partners#metrics"

#       post "oauth/token", to: "partner_callbacks#exchange_token"
#       post "oauth/revoke", to: "partner_callbacks#revoke_token"

#       resources :users, only: [ :show ] do
#         member do
#           get :bonid_profile
#           get :verification_records
#         end
#       end
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # Schema Tools (Partner Integrations)
#   # ----------------------------------------------------------------------------
#   resources :schemas do
#     member do
#       get :preview
#       post :validate_sample
#     end
#   end

#   namespace :partner_portal do
#     resources :schemas
#   end

#   namespace :admin do
#     resources :partner_schemas do
#       member do
#         patch :approve
#         patch :reject
#         patch :deactivate
#       end
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # DEV UTILITIES
#   # ----------------------------------------------------------------------------
#   if Rails.env.development?
#     mount LetterOpenerWeb::Engine, at: "/letter_opener"
#   end
# end




# _____________________________________________________
# BEfore the New Routes
# ___________________________________________________-

# frozen_string_literal: true

#   # === Root & Public Pages ===
#   root "main#home"
#   get "/start",                 to: "main#start",     as: :start_verification
#   get "/partners",              to: "main#partners",  as: :partners
#   get "/partners/verify/:slug", to: "partners#verify", as: :partners_verification
#   get "/favicon.ico",           to: redirect("/assets/favicon.ico")

#   # ----------------------------------------------------------------------------
#   # PUBLIC: QR Verification (read-only, no login required)
#   # ----------------------------------------------------------------------------
#   resources :identity_submissions, only: [] do
#     member { get :verified_profile }
#     collection { get "verify/:token", to: "identity_submissions#verify", as: :verify }
#   end

#   # ----------------------------------------------------------------------------
#   # CITIZENS (User model, citizen role)
#   # ----------------------------------------------------------------------------
#   devise_for :citizens,
#              class_name: "User",
#              path: "citizens",
#              controllers: {
#                registrations: "citizens/registrations",
#                sessions:      "citizens/sessions",
#                passwords:     "devise/passwords",
#                confirmations: "devise/confirmations"
#              },
#              path_names: { sign_up: "sign_up", sign_in: "sign_in", sign_out: "sign_out" }

#   devise_scope :citizen do
#     get   "citizens/otp_sign_in",  to: "citizens/sessions#new_otp",    as: :citizens_otp_sign_in
#     post  "citizens/otp_sign_in",  to: "citizens/sessions#create_otp", as: :citizens_otp_session
#     match "citizens/verify_otp",   to: "citizens/sessions#verify_otp", via: %i[get post], as: :citizens_verify_otp
#     post  "citizens/resend_otp",   to: "citizens/sessions#resend_otp", as: :citizens_resend_otp
#   end

#   # === SINGLE namespace block (no duplicates!) ===
#   namespace :citizens do
#     resource  :profile, only: %i[new create show edit update]

#     resources :identity_submissions do
#       collection do
#         post :request_new
#         get  :verify
#         get  :scan_history
#         get  :support_faq
#       end
#       member do
#         post :request_new
#         post :refresh_qr
#       end
#     end

#     resources :verification_records
#     resources :addresses, only: [ :create ]
#   end

#   namespace :partner_portal do
#     resources :schemas
#   end

#   namespace :admin do
#     resources :partner_schemas do
#       member do
#         patch :approve
#         patch :reject
#         patch :deactivate
#       end
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # ADMIN VERIFICATION RECORDS (Backoffice review)
#   # ----------------------------------------------------------------------------
#   namespace :admin do
#     resources :verification_records, only: %i[index show update]
#   end

#   # ----------------------------------------------------------------------------
#   # EMERGENCY CONTACTS
#   # ----------------------------------------------------------------------------
#   resources :emergency_contacts, only: [] do
#     collection { get :fetch_from_bonid }
#   end

#   # ----------------------------------------------------------------------------
#   # ADMINS (System admins only)
#   # ----------------------------------------------------------------------------
#   devise_for :admin_users,
#              class_name: "AdminUser",
#              path: "admin",
#              controllers: {
#                sessions:  "admin/sessions",
#                passwords: "admin/passwords"
#              },
#              skip: [ :registrations ]

#   namespace :admin do
#     root to: "dashboards#index"
#     get "dashboards/index"

#     resources :partners do
#       get  "dashboard",      to: "partners#dashboard",      as: :partner_dashboard
#       post "invite_officer", to: "partners#invite_officer", as: :invite_officer

#       resources :partner_admin_invitations, only: %i[new create] do
#         get :option_invites, on: :collection
#       end
#       resources :partner_reviewer_invitations, only: %i[new create]
#       resources :officers,    only: %i[index new create show edit update]
#       resources :assignments, only: %i[index new create edit update]

#       member do
#         post :resend_verification_email
#         get  :invite_options
#         get  :invite_single
#         post :send_invite_single
#         get  :invite_bulk
#         post :send_invite_bulk
#       end
#     end

#     resources :guidelines, only: [ :index ] do
#       post :confirm, on: :collection
#     end

#       post :geocode_address, on: :member
#     end

#     resources :incident_reports, only: %i[index show] do
#       member do
#         post :approve
#         post :flag
#         get  :print
#         get  :download_pdf
#         get  :share
#       end
#     end

#     resources :officer_invitations, only: %i[new create]
#     get  "officer_bulk_invitations/new", to: "officer_bulk_invitations#new", as: :new_officer_bulk_invitation
#     post "officer_bulk_invitations",     to: "officer_bulk_invitations#create", as: :officer_bulk_invitations

#     resources :identity_submissions do
#       member do
#         patch :approve
#         patch :reject
#         patch :approve_bin
#         patch :reject_bin
#         patch :approve_reset
#         patch :reject_reset
#         post  :regenerate_qr
#         post  :verify_signature
#       end
#       collection do
#         post  :bulk_update
#         patch :approve_bin, to: "identity_submissions#bulk_approve_bin"
#         patch :reject_bin,  to: "identity_submissions#bulk_reject_bin"
#         post  :fallback_lookup
#       end
#     end

#     resources :qr_scans,     only: [ :index ]
#     resources :qr_scan_logs, only: [ :index ]
#     resources :partner_access_logs, only: [ :index ] # ✅ Added Admin view for access logs
#   end

#   # ----------------------------------------------------------------------------
#   # PUBLIC: Partner Applications (signup flow)
#   # ----------------------------------------------------------------------------

#   # ----------------------------------------------------------------------------
#   # PARTNER ADMINS (User model, partner_admin role)
#   # ----------------------------------------------------------------------------
#   # devise_for :partner_admins,
#   #            class_name: "User",
#   #            path: "partner_admin",
#   #            controllers: {
#   #              sessions: "partners/sessions",
#   #   invitations: "partners/invitations",
#   #   passwords: "partners/passwords",
#   #   confirmations: "partners/confirmations"
#   #            },
#   #            skip: [ :registrations, :confirmations ]
#   #
#   # === Partner Admin Portal ===
#   # ----------------------------------------------------------------------------
#   # PARTNER ADMINS (User model, partner_admin role)
#   # ----------------------------------------------------------------------------
#   devise_for :partner_admins,
#            class_name: "PartnerAdmin",
#            path: "partner_admin",
#            controllers: {
#              sessions: "partner_portal/partner_admin/sessions",
#              passwords: "partner_portal/partner_admin/passwords",
#              invitations: "partner_portal/partner_admin/invitations",
#              registrations: "devise_invitable/registrations"
#            }


#   devise_for :banking_agents,
#              class_name: "BankingAgent",
#              path: "banking_agents",
#              controllers: {
#                invitations: "partner_portal/banking_agents/invitations",
#                sessions: "partner_portal/banking_agents/sessions",
#                passwords: "partner_portal/banking_agents/passwords",
#                registrations: "partner_portal/banking_agents/registrations"
#              }

#   # ----------------------------------------------------------------------------
#   # PARTNER PORTAL (All Sectors)
#   # ----------------------------------------------------------------------------
#   namespace :partner_portal do
#     root to: redirect { |_params, req|
#       user   = req.env["warden"].user(:partner_admin)
#       sector = user&.partner&.sector&.downcase

#       case sector
#       when "law_enforcement"
#         "/partner_portal/law_enforcement/dashboard"
#       when "banking", "financial_services", "fintech", "insurance"
#         "/partner_portal/banking/dashboard"
#       when "hospital", "healthcare"
#         "/partner_portal/hospital/dashboard"
#       when "embassy", "embassy_services"
#         "/partner_portal/embassy/dashboard"
#       else
#         "/partner_portal/dashboard"
#       end
#     }

#     get "dashboard", to: "dashboard#index"

#     # ✅ Partner Access Logs route
#     resources :access_logs, only: [ :index ]

#     # --- Law Enforcement Portal ---
#     namespace :law_enforcement do
#       get "dashboard", to: "dashboard#index"
#       resources :officers
#       resources :incident_reports
#       resources :tickets
#     end

#     # --- Banking Portal ---
#     namespace :banking do
#       root to: redirect("/partner_portal/banking/dashboard")

#       get "dashboard",     to: "dashboard#index",     as: :dashboard
#       get "api_docs",      to: "api_docs#index",      as: :api_docs
#       get "api_keys",      to: "api_keys#index",      as: :api_keys
#       get "reports",       to: "reports#index",       as: :reports
#       get "customers",     to: "customers#index",     as: :customers
#       get "transactions",  to: "transactions#index",  as: :transactions
#       get "settings",      to: "settings#index",      as: :settings
#       get "support",       to: "support#index",       as: :support

#       post "bonid_lookup", to: "verifications#lookup", as: :bonid_lookup
#       get  "kyc/new/:user_id", to: "kyc_requests#new", as: :new_kyc
#       get  "kyc", to: "kyc#index", as: :kyc

#       resources :agents, only: [ :new, :create, :index ] do
#         collection do
#           get  :invite_bulk
#           post :send_bulk_invite
#         end

#         member do
#           post :resend_invite
#         end

#         resources :kyc_requests, only: [ :new ] do
#           post :verify, on: :member
#           post :flag,   on: :member
#         end
#       end

#       resources :partners, only: %i[index show]

#       # ✅ Add Teller Scans route correctly here
#       resources :teller_scans, only: [ :index ]
#     end

#     # --- Hospital Portal ---
#     namespace :hospital do
#       get "dashboard", to: "dashboard#index"
#       resources :records, only: [ :show ] do
#         patch :verify, on: :member
#       end
#     end

#     # --- Embassy Portal ---
#     namespace :embassy do
#       get "dashboard", to: "dashboard#index"
#       resources :partners, only: %i[index show]
#     end

#     # --- Shared Partner Utilities ---
#     resources :partners, only: [] do
#       member do
#         get :dashboard
#         get :invite_options
#         get :invite_single
#         post :send_invite_single
#         get :invite_bulk
#         post :send_invite_bulk
#       end
#     end

#     resources :officer_invitations, only: %i[new create destroy] do
#       collection do
#         get  :bulk_new
#         post :bulk_create
#       end
#       member { post :resend }
#     end

#     resources :bonid_lookups, only: %i[index show create] do
#       collection do
#         get :manual
#         get :failed
#       end
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # REVIEWERS
#   # ----------------------------------------------------------------------------
#   devise_for :reviewers,
#              class_name: "User",
#              path: "reviewer",
#              controllers: {
#                sessions:  "reviewer/sessions",
#                passwords: "reviewer/passwords"
#              },
#              skip: [ :registrations ]

#   # ----------------------------------------------------------------------------
#   # OFFICERS
#   # ----------------------------------------------------------------------------
#   devise_for :officers,
#              class_name: "User",
#              path: "officers",
#              controllers: {
#                sessions:    "officers/sessions",
#                passwords:   "officers/passwords",
#                invitations: "officers/invitations"
#              },
#              skip: [ :registrations ]

#   devise_scope :officer do
#     get "officers/invalid", to: redirect("/reviewer/sign_in")
#   end

#   namespace :officers do
#     get  "dashboard",               to: "dashboard#index",        as: :dashboard
#     get  "dashboard/drafts",        to: "dashboard#drafts",       as: :dashboard_drafts
#     get  "dashboard/crime_reports", to: "dashboard#crime_reports"
#     get  "dashboard/recent_scans",  to: "dashboard#recent_scans"
#     get  "dashboard/failed_scans",  to: "dashboard#failed_scans"
#     get  "dashboard/:id",           to: "dashboard#show",         as: :dashboard_show

#     get   "profile/edit", to: "profiles#edit",   as: :edit_profile
#     patch "profile",      to: "profiles#update", as: :profile

#     resources :person_involvements, only: [] do
#       get :fetch_identity, on: :collection
#     end

#     resources :incident_reports do
#       collection do
#         get :bonid_lookup_manual
#         get :export_csv
#       end
#       member do
#         post :approve
#         post :flag
#         get  :print
#         get  :download_pdf
#         get  :share
#       end
#     end

#     resources :tickets
#     resources :bonid_lookups do
#       collection do
#         get :manual
#         get :failed
#       end
#     end
#     post "bonid_lookup", to: "bonid_lookups#create", as: :officers_bonid_lookup

#     get  "scan",         to: "scans#new",        as: :scan_qr_code
#     post "scan",         to: "scans#create"
#     post "scan_qrcode",  to: "scans#create_qrcode"

#     get "suspect_preview", to: "suspects#preview", as: :suspect_preview
#   end

#   # ----------------------------------------------------------------------------
#   # BANKS Ready API
#   # ----------------------------------------------------------------------------
#   resources :banks, only: [] do
#     collection { get :swift_lookup }
#   end

#   # ----------------------------------------------------------------------------
#   # SHARED UTILITIES
#   # ----------------------------------------------------------------------------
#   get "/departments/:slug/arrondissements", to: "departments#arrondissements",   as: :department_arrondissements
#   get "/arrondissements/:id/communes",      to: "arrondissements#communes",      as: :arrondissement_communes
#   get "/communes/:id/communal_sections",    to: "communes#communal_sections",    as: :commune_communal_sections
#   get "/communal_sections/:id/postal_code", to: "communal_sections#postal_code", as: :communal_section_postal_code
#   get "/communes", to: "communes#index"

#   get "/terms.pdf",   to: "pdfs#terms",   as: :terms_pdf
#   get "/privacy.pdf", to: "pdfs#privacy", as: :privacy_pdf

#   get "/up", to: "rails/health#show", as: :rails_health_check

#   # ----------------------------------------------------------------------------
#   # API (BonID Scalable API v1)
#   # ----------------------------------------------------------------------------
#   namespace :api do
#     namespace :v1 do
#       resources :users, only: [ :show ] do
#         member do
#           get :bonid_profile
#           get :verification_records
#         end
#       end
#     end
#   end

#   resources :schemas do
#     member do
#       get :preview
#       post :validate_sample
#     end
#   end

#   # ----------------------------------------------------------------------------
#   # DEV ENV UTILITIES
#   # ----------------------------------------------------------------------------
#   if Rails.env.development?
#     mount LetterOpenerWeb::Engine, at: "/letter_opener"
#   end
# end
