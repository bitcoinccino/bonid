# frozen_string_literal: true

module Citizens
  class ServicesController < ApplicationController
    before_action :authenticate_citizen!
    layout "citizen"

    # ================================================================
    # SECTOR → ICON mapping for UI display
    # ================================================================
    SECTOR_ICONS = {
      "Government"              => "ri-government-line",
      "Finance"                 => "ri-bank-line",
      "Fintech & Mobile Money"  => "ri-wallet-3-line",
      "Law Enforcement"         => "ri-shield-star-line",
      "Diplomacy"               => "ri-global-line",
      "Healthcare"              => "ri-hospital-line",
      "Education"               => "ri-graduation-cap-line",
      "Telecom"                 => "ri-signal-tower-line",
      "Insurance"               => "ri-shield-check-line",
      "Tourism & Hospitality"   => "ri-hotel-line",
      "NGO & International"     => "ri-hand-heart-line",
      "Real Estate"             => "ri-home-3-line",
      "Legal"                   => "ri-scales-3-line",
      "Logistics & Transport"   => "ri-truck-line",
      "Gaming & Lottery"        => "ri-game-line",
      "Energy & Utilities"      => "ri-flashlight-line",
      "Culture & Media"         => "ri-palette-line",
      "Agriculture & Environment" => "ri-plant-line",
      "Professional Services"   => "ri-briefcase-line"
    }.freeze

    # ================================================================
    # SECTOR → COLOR for category badges
    # ================================================================
    SECTOR_COLORS = {
      "Government"              => "#00209F",
      "Finance"                 => "#0D6E3F",
      "Fintech & Mobile Money"  => "#7C3AED",
      "Law Enforcement"         => "#092C73",
      "Diplomacy"               => "#1D4ED8",
      "Healthcare"              => "#DC2626",
      "Education"               => "#D97706",
      "Telecom"                 => "#0891B2",
      "Insurance"               => "#4F46E5",
      "Tourism & Hospitality"   => "#E11D48",
      "NGO & International"     => "#059669",
      "Real Estate"             => "#78716C",
      "Legal"                   => "#6D28D9",
      "Logistics & Transport"   => "#EA580C",
      "Gaming & Lottery"        => "#BE185D",
      "Energy & Utilities"      => "#CA8A04",
      "Culture & Media"         => "#DB2777",
      "Agriculture & Environment" => "#16A34A",
      "Professional Services"   => "#475569"
    }.freeze

    # ================================================================
    # DGI service definitions (the only fully live services right now)
    # ================================================================
    DGI_SERVICES = [
      { key: "nif_registration",      name: "Enskripsyon NIF",   desc: "Formulaire A — Nimewo Idantifikasyon Fiskal", icon: "ri-file-text-line" },
      { key: "business_registration", name: "Anrejistreman Biznis", desc: "Formulaire B — Anrejistreman antrepriz",  icon: "ri-store-2-line" },
      { key: "patente_declaration",   name: "Deklarasyon Patant",  desc: "DGI-F008 — Taks lisans biznis",             icon: "ri-file-list-3-line" },
      { key: "tca_declaration",       name: "Deklarasyon TCA",     desc: "TCA — 10% taks sou lavant",                 icon: "ri-percent-line" },
      { key: "ras_ir_declaration",    name: "Deklarasyon RAS/IR",  desc: "DGI-F005 — Taks sou salè",                  icon: "ri-money-dollar-circle-line" },
      { key: "fermage",              name: "Fermaj",               desc: "DGI-55 — Taks sou lwaye tè",                icon: "ri-landscape-line" }
    ].freeze

    # ================================================================
    # GET /citizens/services
    # Browse all approved partners grouped by sector category
    # ================================================================
    PER_PAGE = 12

    def index
      @verified = current_citizen.identity_submissions.where(status: :approved).exists?
      @search = params[:search].to_s.strip
      @sector_filter = params[:sector].to_s.strip
      @page = [params[:page].to_i, 1].max

      partners = Partner.where(status: :approved, active: true, deleted_at: nil)
                        .with_attached_logo

      # Search by name
      if @search.present?
        partners = partners.where("LOWER(name) LIKE ?", "%#{@search.downcase}%")
      end

      # Filter by sector group
      if @sector_filter.present?
        sector_list = PartnerSectorConstants::SECTORS[@sector_filter]
        partners = partners.where(sector: sector_list) if sector_list
      end

      partners = partners.order(:name)

      # Total count before pagination
      @total_count = partners.count
      @limit = @page * PER_PAGE
      @has_more = @total_count > @limit

      # Paginate
      partners = partners.limit(@limit)

      # Group partners by their sector category
      @grouped_partners = {}
      PartnerSectorConstants::SECTORS.each do |group_name, sector_list|
        next if @sector_filter.present? && group_name != @sector_filter

        group_partners = partners.select { |p| sector_list.include?(p.sector) }
        next if group_partners.empty?

        @grouped_partners[group_name] = group_partners
      end

      @sector_icons  = SECTOR_ICONS
      @sector_colors = SECTOR_COLORS
      @sector_groups = PartnerSectorConstants::SECTORS.keys
    end

    # ================================================================
    # GET /citizens/services/:slug
    # Show a specific partner's detail page + available services
    # ================================================================
    def show
      @partner = Partner.with_attached_logo.find_by!(slug: params[:slug], status: :approved, active: true, deleted_at: nil)
      @verified = current_citizen.identity_submissions.where(status: :approved).exists?

      # Determine which sector group this partner belongs to
      @sector_group = PartnerSectorConstants::SECTORS.find { |_group, sectors| sectors.include?(@partner.sector) }&.first
      @sector_icon  = SECTOR_ICONS[@sector_group] || "ri-building-line"
      @sector_color = SECTOR_COLORS[@sector_group] || "#6B7280"

      # Load services based on partner sector
      @services = services_for(@partner)
      @has_live_services = @services.any? { |s| s[:status] == :live }
    end

    # ================================================================
    # GET /citizens/service/:partner_slug/:schema_id
    # Service detail / product page before applying
    # ================================================================
    def detail
      @partner = Partner.with_attached_logo.find_by!(slug: params[:partner_slug], status: :approved, active: true, deleted_at: nil)
      @schema = @partner.partner_schemas.find_by!(form_code: params[:form_code])
      @verified = current_citizen.identity_submissions.where(status: :approved).exists?

      @sector_group = PartnerSectorConstants::SECTORS.find { |_group, sectors| sectors.include?(@partner.sector) }&.first
      @sector_color = SECTOR_COLORS[@sector_group] || "#6B7280"

      @has_pricing = @schema.price_cents.to_i > 0 || Array(@schema.structure&.dig("fields")).any? { |f| f["has_pricing"] }
      @apply_path = citizens_apply_service_path(partner_slug: @partner.slug, form_code: @schema.form_code)
    end

    private

    def services_for(partner)
      services = []

      # DGI legacy services (hardcoded — these use the DGI self-filing flow)
      if partner.sector == "dgi"
        services += DGI_SERVICES.map do |svc|
          svc.merge(status: :live, path: new_citizens_dgi_path(form_type: svc[:key]))
        end
      end

      # Dynamic services from PartnerSchema (published, citizen-facing)
      partner.partner_schemas
             .where(citizen_facing: true, active: true, schema_status: "published")
             .order(position: :asc, created_at: :desc)
             .each do |schema|
        services << {
          key: schema.record_type,
          name: schema.name,
          desc: schema.description.presence || schema.name,
          icon: schema.service_icon || "ri-file-text-line",
          status: :live,
          path: citizens_service_detail_path(partner_slug: partner.slug, form_code: schema.form_code),
          category: schema.service_category,
          price: schema.price_display,
          cover_image: schema.cover_image.attached? ? schema.cover_image : nil
        }
      end

      # Sector-specific fallback placeholders (only if no dynamic services)
      if services.empty?
        services += sector_placeholder_services(partner)
      end

      services
    end

    def sector_placeholder_services(partner)
      case partner.sector
      when "commercial_bank", "microfinance", "credit_union", "money_transfer",
           "mobile_wallet", "payment_processor", "remittance", "fintech"
        [
          { key: "account_opening", name: "Ouvri yon kont", desc: "Ouvri yon kont labank ak BonID ou",
            icon: "ri-bank-card-line", status: :coming_soon },
          { key: "kyc_verification", name: "Verifikasyon KYC", desc: "Verifye idantite ou pou sèvis finansye",
            icon: "ri-shield-check-line", status: :coming_soon }
        ]
      when "oni"
        [{ key: "cin_application", name: "Mande CIN", desc: "Aplike pou Kat Idantite Nasyonal",
            icon: "ri-id-card-line", status: :coming_soon }]
      when "onaca"
        [{ key: "cadastral_plan", name: "Plan Kadastral", desc: "Jwenn yon plan kadastral pou tè ou",
            icon: "ri-map-2-line", status: :coming_soon }]
      when "archives_nationales"
        [
          { key: "birth_certificate", name: "Ekstrè Nesans", desc: "Mande yon ekstrè ak nesans",
            icon: "ri-file-text-line", status: :coming_soon },
          { key: "marriage_certificate", name: "Ekstrè Maryaj", desc: "Mande yon ekstrè maryaj",
            icon: "ri-heart-2-line", status: :coming_soon }
        ]
      when "immigration", "customs"
        [{ key: "passport_application", name: "Aplike pou Paspò", desc: "Soumèt aplikasyon paspò ou",
            icon: "ri-passport-line", status: :coming_soon }]
      when "cep"
        [{ key: "voter_registration", name: "Enskripsyon Elektoral", desc: "Enskri pou vote nan eleksyon",
            icon: "ri-checkbox-circle-line", status: :coming_soon }]
      else
        [{ key: "identity_verification", name: "Verifikasyon Idantite", desc: "Verifye idantite ou ak #{partner.name}",
            icon: "ri-shield-keyhole-line", status: :coming_soon }]
      end
    end
  end
end
