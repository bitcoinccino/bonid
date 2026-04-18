# frozen_string_literal: true

module PartnerPortal
  class BaseController < ::ApplicationController
    include Devise::Controllers::Helpers

    protect_from_forgery with: :exception, unless: -> { request.format.json? }

    before_action :authenticate_partner_admin!
    before_action :assign_portal_user
    before_action :set_current_partner
    before_action :ensure_correct_sector
    before_action :ensure_partner_portal_access!
    before_action :ensure_profile_complete!
    before_action :ensure_guidelines_accepted!

    helper_method :current_partner, :current_portal_user
    layout :resolve_layout

    # ✅ ALLOWED SECTORS FOR PARTNER PORTAL
    # All sectors from PartnerSectorConstants + legacy values
    ALLOWED_SECTORS = (
      PartnerSectorConstants::SECTORS.values.flatten +
      %w[law_enforcement banking healthcare embassy_services telecom ngo education insurance tourism]
    ).uniq.freeze

    # Maps DB-stored sector values to their portal namespace.
    # Needed when the stored sector value differs from the namespace name
    # (e.g. PNH partners are stored as "pnh" but use the "law_enforcement" namespace/layout).
    SECTOR_NAMESPACE_MAP = {
      "pnh" => "law_enforcement"
    }.freeze

    LAYOUTS = {
      "law_enforcement" => "partner_portal/law_enforcement",
      "pnh"             => "partner_portal/law_enforcement"
    }.freeze

    # Controllers shared across portals (NOT sector-gated)
    GLOBAL_CONTROLLERS = %w[
      dashboard access_logs support settings api_docs api_keys reports partners schemas services
      fiscal_receipts verifications analytics scans bonid_lookups team credits billing submissions
      nif_registrations business_registrations patente_declarations tca_declarations ras_ir_declarations
      dgi_review dgi_cash_payments election_dashboard electoral_calendar voter_eligibility
      voter_registry polling_centers candidate_registrations party_registrations partner_audit_logs
      accreditations
    ].freeze

    private

    # ============================================================
    # AUTH (Partner Admin Only)
    # ============================================================
    def authenticate_partner_admin!
      return if partner_admin_signed_in?

      redirect_to new_partner_admin_session_path,
                  alert: "Please sign in to your Partner Portal."
    end

    def assign_portal_user
      @current_portal_user = current_partner_admin
      Rails.logger.info "✅ PartnerAdmin authenticated: ##{@current_portal_user&.id}"
    end

    # ============================================================
    # PARTNER CONTEXT
    # ============================================================
    def set_current_partner
      @current_partner = @current_portal_user&.partner
      return if @current_partner.present?

      Rails.logger.warn "⚠️ PartnerAdmin ##{@current_portal_user&.id} has NO partner assigned"
      redirect_to new_partner_admin_session_path,
                  alert: "Your account is missing a partner association."
    end

    def current_partner
      @current_partner
    end

    def current_portal_user
      @current_portal_user
    end

    # ============================================================
    # SECTOR AUTHORIZATION (LAW ENFORCEMENT ONLY)
    # ============================================================
    def ensure_correct_sector
      return if @current_partner.nil?

      partner_sector = @current_partner.sector.to_s.downcase

      # If partner itself is not enabled for portal access, block immediately.
      unless ALLOWED_SECTORS.include?(partner_sector)
        Rails.logger.warn("🚨 Partner has unsupported sector: #{partner_sector.inspect}")
        return safe_partner_redirect("Your partner sector is not enabled for portal access.")
      end

      controller_full_name = self.class.name
      controller_name_part = controller_full_name.split("::").last.sub("Controller", "").underscore

      # Global/shared controllers are always allowed.
      return if GLOBAL_CONTROLLERS.include?(controller_name_part)

      # Sector namespace pattern: PartnerPortal::LawEnforcement::XController
      namespace = controller_full_name.split("::")[1].to_s.underscore # "law_enforcement", "dashboard", etc.

      # If this controller isn't under a sector namespace, treat it as global.
      return unless namespace.present?

      # Only gate sector namespaces we support.
      return unless ALLOWED_SECTORS.include?(namespace)

      # Resolve the partner's effective namespace — some sectors (e.g. "pnh") map
      # to a shared namespace (e.g. "law_enforcement") via SECTOR_NAMESPACE_MAP.
      effective_namespace = SECTOR_NAMESPACE_MAP.fetch(partner_sector, partner_sector)

      # Must match the controller's namespace
      return if namespace == effective_namespace

      Rails.logger.warn("🚨 Unauthorized sector access: namespace=#{namespace} partner_sector=#{partner_sector} effective=#{effective_namespace}")
      safe_partner_redirect("You are not authorized to access the #{namespace.titleize} Portal.")
    end

    # ============================================================
    # PARTNER STATUS
    # ============================================================
    def ensure_partner_portal_access!
      if current_partner&.deleted?
        redirect_to partner_portal_disabled_path, alert: "This partner account has been deleted."
      elsif current_partner&.suspended?
        redirect_to partner_portal_suspended_path, alert: "This partner account is suspended."
      end
    end

    # ============================================================
    # LAYOUT
    # ============================================================
    def resolve_layout
      sector = @current_partner&.sector.to_s.downcase
      LAYOUTS[sector] || "partner_portal/default"
    end

    # ============================================================
    # PROFILE COMPLETION GATE
    # ============================================================
    def ensure_profile_complete!
      return unless @current_partner.present?

      # Skip check for profile completion controller itself
      return if self.class.name.include?("ProfileCompletion")

      # Skip check for session/auth controllers
      return if self.class.name.include?("Sessions")

      unless profile_complete?(@current_partner)
        redirect_to partner_portal_profile_completion_path,
                    alert: "Please complete your profile to access the Partner Portal."
      end
    end

    def profile_complete?(partner)
      return false unless partner.present?

      # Required fields for profile completion
      partner.description.present? &&
        partner.contact_person.present? &&
        partner.phone_number.present?
    end

    # ============================================================
    # GUIDELINES ACCEPTANCE GATE
    # ============================================================
    def ensure_guidelines_accepted!
      return unless @current_partner.present?

      # Skip check for guidelines controller itself
      return if self.class.name.include?("GuidelinesAcceptance")

      # Skip check for profile completion & session controllers
      return if self.class.name.include?("ProfileCompletion")
      return if self.class.name.include?("Sessions")

      unless guidelines_accepted?(@current_partner)
        redirect_to partner_portal_guidelines_path,
                    alert: "Tanpri li epi aksepte direktiv BonID yo anvan ou ka itilize Portal Patnè a."
      end
    end

    def guidelines_accepted?(partner)
      return false unless partner.present?

      partner.guidelines_accepted_at.present? &&
        partner.guidelines_version == PartnerPortal::GuidelinesAcceptanceController::CURRENT_VERSION
    end

    # ============================================================
    # BONID AUTO-FILL (shared across DGI form controllers)
    # ============================================================
    def build_auto_fill(citizen)
      return {} unless citizen

      addr = citizen.address
      nif_record = citizen.verification_records
                     .where(record_type: "nif_registration", status: "verified")
                     .order(created_at: :desc).first
      {
        first_name:        citizen.first_name,
        last_name:         citizen.last_name,
        full_name:         "#{citizen.last_name} #{citizen.first_name}".strip,
        phone:             citizen.phone,
        email:             citizen.email,
        street_address:    addr&.street_address || citizen.street_address,
        locality:          addr&.locality || citizen.locality,
        department:        addr&.department&.name || citizen.birth_department&.name,
        commune:           addr&.commune&.name || citizen.birth_commune&.name,
        section_communale: addr&.communal_section&.name,
        postal_code:       addr&.postal_code || citizen.postal_code,
        country:           addr&.country || "Haiti",
        birth_department:  addr&.department&.name || citizen.birth_department&.name,
        birth_commune:     addr&.commune&.name || citizen.birth_commune&.name,
        date_of_birth:     citizen.dob,
        sex:               { "male" => "M", "female" => "F" }[citizen.sex] || citizen.sex,
        nationality:       citizen.nationality || "Ayisyen",
        cin:               citizen.id_number,
        nif:               nif_record&.nif_genere
      }
    end

    # ============================================================
    # SAFE REDIRECT
    # ============================================================
    def safe_partner_redirect(alert_msg = "Access restricted to your Partner Portal.")
      redirect_to ::PartnerPortalRouter.dashboard_path_for(@current_portal_user),
                  alert: alert_msg
    end
  end
end
