Rails.application.routes.draw do
  # === Root & Public Pages ===
  root "main#home"
  get "/start", to: "main#start", as: :start_verification
  get "/partners", to: "main#partners", as: :partners
  get "/partners/verify/:slug", to: "partners#verify", as: :partners_verification
  get "/verify/:verification_token", to: "identity_submissions#verify", as: :verify_identity_submission
  get "/dashboard", to: "identity_submissions#index", as: :user_dashboard

  # === Devise Auth ===
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }

  devise_for :officers, path: "officer_auth", controllers: {
    sessions: "officers/sessions",
    registrations: "officers/registrations",
    passwords: "officers/passwords"
  }

  # === Profile & Identity Submissions ===
  resource :profile, only: [:edit, :update]
  resources :identity_submissions, only: [:index, :new, :create, :show]
  post "/request_new_bonid", to: "identity_submissions#request_new", as: :request_new_bonid
  

  # === Partner Applications ===
  resources :partner_applications, only: [:new, :create, :show]

  # === Admin Namespace ===
  namespace :admin do
    resources :guidelines, only: [:index] do
      post :confirm, on: :collection
    end
    resources :partner_applications, only: [:index, :show, :edit, :update] do
      member do
        post :geocode_address
      end
    end
    resources :partners do
      post :resend_verification_email, on: :member
      resources :officers, only: [:index, :new, :create]
    end

    resources :identity_submissions do
      member do
        patch :approve
        patch :reject
        patch :approve_bin
        patch :reject_bin
        patch :approve_reset
        patch :reject_reset
      end
      collection do
        post :bulk_update
        patch :approve_bin, to: "identity_submissions#bulk_approve_bin"
        patch :reject_bin,  to: "identity_submissions#bulk_reject_bin"
      end
    end

    resources :qr_scans, only: [:index]
    resources :qr_scan_logs, only: [:index]

    resources :incident_reports do
      member do
        post :approve
        post :flag
      end
    end
  end

  # === Officer Flow ===
  get   "/officers/invite/:token", to: "officers#accept_invitation", as: :accept_officer_invitation
  put   "/officers/invite/:token", to: "officers#accept_invitation"
  get   "/officer/dashboard",      to: "officers#dashboard",          as: :officer_dashboard
  get   "/officer/profile/edit",   to: "officers#edit",               as: :edit_officer_profile
  patch "/officer/profile",        to: "officers#update",             as: :officer_profile

  get   "/officer/reports/new",    to: "officers#new_incident_report",    as: :new_officer_incident_report
  post  "/officer/reports",        to: "officers#create_incident_report", as: :create_officer_incident_report

  get   "/officer/bonid_lookup/:bonid", to: "officers/incident_reports#bonid_lookup", as: :bonid_lookup
  get   "/officer/scan",               to: "officers#scan",                    as: :scan_qr_code
  post  "/officers/scan_qrcode",       to: "officers#scan_qrcode"
  get   "/officers/scan_bonid",        to: "officers#scan_bonid"

  # === Address Lookups ===
  get "/departments/:slug/arrondissements",      to: "departments#arrondissements",       as: :department_arrondissements
  get "/arrondissements/:id/communes",           to: "arrondissements#communes",          as: :arrondissement_communes
  get "/communes/:id/communal_sections",         to: "communes#communal_sections",        as: :commune_communal_sections
  get "/communal_sections/:id/postal_code",      to: "postal_codes#lookup",               as: :communal_section_postal_code

  # === Legal PDFs ===
  get "/terms.pdf",   to: "pdfs#terms",   as: :terms_pdf
  get "/privacy.pdf", to: "pdfs#privacy", as: :privacy_pdf

  # === Health Check ===
  get "up", to: "rails/health#show", as: :rails_health_check
end
