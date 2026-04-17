# app/controllers/partner_portal/dashboard_controller.rb
module PartnerPortal
  class DashboardController < PartnerPortal::BaseController
    layout "partner_portal/default"

    def index
      unless @current_partner
        redirect_to partner_portal_applications_path, alert: "No partner profile associated." and return
      end

      unless @current_partner.verified_at?
        redirect_to partner_portal_applications_path, alert: "Partner verification required." and return
      end

      # Check if profile needs completion (for PNH minimal signups)
      if profile_incomplete?
        redirect_to partner_portal_profile_completion_path,
                    notice: "Please complete your profile to access your dashboard." and return
      end

      # Check department_sector first (new system), then fallback to sector (legacy)
      partner_sector = @current_partner.department_sector || @current_partner.sector

      case partner_sector&.downcase
      when "pnh", "law_enforcement"
        redirect_to partner_portal_law_enforcement_dashboard_path and return
      when "dgi"
        load_dgi_dashboard_data
        load_submissions_data
        return render "partner_portal/dashboard/dgi"
      when "immigration"
        load_immigration_dashboard_data
        load_submissions_data
        return render "partner_portal/dashboard/immigration"
      when "embassy", "consulate", "international_org", "un_agency"
        load_embassy_dashboard_data
        load_submissions_data
        return render "partner_portal/dashboard/embassy"
      when "onaca"
        load_onaca_dashboard_data
        load_submissions_data
        return render "partner_portal/dashboard/onaca"
      when "commercial_bank", "microfinance", "credit_union", "money_transfer",
           "mobile_wallet", "payment_processor", "remittance", "fintech", "banking"
        load_banking_dashboard_data
        load_submissions_data
        return render "partner_portal/dashboard/banking"
      end

      # Default dashboard for all other sectors
      load_default_dashboard_data
      load_submissions_data
    end

    private

    def load_default_dashboard_data
      @partner = @current_partner

      # Stats
      @stats = {
        qr_scans: @partner.qr_scans.count,
        qr_scans_today: @partner.qr_scans.where("created_at >= ?", Time.current.beginning_of_day).count,
        verifications: @partner.verification_records.count,
        consent_grants: @partner.consent_grants.count
      }

      # Recent activity
      @recent_scans = @partner.qr_scans
                        .includes(identity_submission: :user)
                        .order(created_at: :desc)
                        .limit(10)

      @recent_verifications = @partner.verification_records
                                .order(created_at: :desc)
                                .limit(10)

      # API stats
      @api_stats = {
        total: @partner.api_access_logs.count,
        success: @partner.api_access_logs.where(success: true).count,
        failed: @partner.api_access_logs.where(success: false).count,
        today: @partner.api_access_logs.where("created_at >= ?", Time.current.beginning_of_day).count
      }

      # Consent grants (citizens who authorized this partner)
      @consent_grants = @partner.consent_grants
                          .includes(:citizen)
                          .where(status: :approved)
                          .order(created_at: :desc)
                          .limit(10)

      # Transaction consents (ephemeral per-transaction approvals)
      @transaction_consents = @partner.transaction_consents
                                .includes(:citizen)
                                .order(created_at: :desc)
                                .limit(10)
    end

    # ============================================================
    # DGI Dashboard Data
    # ============================================================
    def load_dgi_dashboard_data
      @partner = @current_partner

      # --- Fiscal receipts (partner-issued) ---
      fiscal = @partner.verification_records.where(record_type: "fiscal_receipt")
      today_fiscal = fiscal.where("created_at >= ?", Time.current.beginning_of_day)

      # --- Citizen-filed declarations (all DGI form types) ---
      citizen_form_types = %w[
        nif_registration business_registration
        patente_declaration tca_declaration ras_ir_declaration
        fermage
      ]
      citizen_declarations = VerificationRecord.where(record_type: citizen_form_types)
      today_citizen = citizen_declarations.where("created_at >= ?", Time.current.beginning_of_day)

      # --- DGI Payments ---
      all_payments = DgiPayment.where(status: "completed")
      today_payments = all_payments.where("paid_at >= ?", Time.current.beginning_of_day)

      @stats = {
        # Fiscal receipt stats (partner-issued)
        total_receipts: fiscal.count,
        receipts_today: today_fiscal.count,
        fiscal_revenue_htg: fiscal.sum { |r| r.data.dig("receipt", "amount_htg").to_i },

        # Citizen declaration stats
        total_declarations: citizen_declarations.count,
        declarations_today: today_citizen.count,
        declarations_pending: citizen_declarations.where(status: "pending").count,
        declarations_verified: citizen_declarations.where(status: "verified").count,
        declarations_rejected: citizen_declarations.where(status: "rejected").count,

        # Payment stats (DgiPayment)
        total_payments: all_payments.count,
        payments_today: today_payments.count,
        revenue_today_htg: today_payments.sum(:amount_htg).to_i + today_payments.sum(:fee_htg).to_i,
        total_revenue_htg: all_payments.sum(:amount_htg).to_i + all_payments.sum(:fee_htg).to_i,
        dgi_revenue_htg: all_payments.sum(:amount_htg).to_i,
        bonid_fees_htg: all_payments.sum(:fee_htg).to_i,

        # Combined
        verified: citizen_declarations.where(status: "verified").count + fiscal.where(status: "verified").count,
        consumed: fiscal.where("data->'consumption'->>'consumed' = ?", "true").count,
        consent_grants: @partner.consent_grants.count
      }

      # Revenue by tax type (for chart)
      @revenue_by_tax_type = {}
      fiscal.find_each do |r|
        tax = r.data.dig("receipt", "tax_type") || "other"
        @revenue_by_tax_type[tax] ||= 0
        @revenue_by_tax_type[tax] += r.data.dig("receipt", "amount_htg").to_i
      end
      # Add citizen declaration payment revenue by form type
      all_payments.includes(:verification_record).find_each do |p|
        form_type = p.verification_record&.record_type || "other"
        @revenue_by_tax_type[form_type] ||= 0
        @revenue_by_tax_type[form_type] += p.amount_htg.to_i
      end
      @revenue_by_tax_type = @revenue_by_tax_type.sort_by { |_, v| -v }.to_h

      # Recent receipts (fiscal)
      @recent_receipts = fiscal.order(created_at: :desc).limit(10)

      # Recent citizen declarations
      @recent_declarations = citizen_declarations.order(created_at: :desc).limit(10)

      # Recent payments
      @recent_payments = all_payments.order(paid_at: :desc).limit(10)

      # Receipts by day (last 14 days)
      @receipts_by_day = fiscal
        .where("created_at >= ?", 14.days.ago)
        .group("DATE(created_at)")
        .order("DATE(created_at)")
        .count

      # API stats
      @api_stats = {
        total: @partner.api_access_logs.count,
        today: @partner.api_access_logs.where("created_at >= ?", Time.current.beginning_of_day).count
      }
    end

    # ============================================================
    # Immigration (DIE) Dashboard Data
    # ============================================================
    def load_immigration_dashboard_data
      @partner = @current_partner

      scans = @partner.qr_scans
      today_scans = scans.where("created_at >= ?", Time.current.beginning_of_day)
      verifications = @partner.verification_records
      today_verifications = verifications.where("created_at >= ?", Time.current.beginning_of_day)

      @stats = {
        total_scans: scans.count,
        scans_today: today_scans.count,
        verifications: verifications.count,
        verified_today: today_verifications.where(status: "verified").count,
        passports_processed: verifications.where(record_type: "passport").count,
        consent_grants: @partner.consent_grants.count
      }

      # Recent scans
      @recent_scans = scans
                        .includes(identity_submission: :user)
                        .order(created_at: :desc)
                        .limit(10)

      # Scans by day (last 14 days)
      @scans_by_day = scans
        .where("created_at >= ?", 14.days.ago)
        .group("DATE(created_at)")
        .order("DATE(created_at)")
        .count

      # API stats
      @api_stats = {
        total: @partner.api_access_logs.count,
        today: @partner.api_access_logs.where("created_at >= ?", Time.current.beginning_of_day).count
      }
    end

    # ============================================================
    # Embassy / Consulate (BonVisa) Dashboard Data
    # ============================================================
    def load_embassy_dashboard_data
      @partner = @current_partner

      scans = @partner.qr_scans
      today_scans = scans.where("created_at >= ?", Time.current.beginning_of_day)
      verifications = @partner.verification_records
      today_verifications = verifications.where("created_at >= ?", Time.current.beginning_of_day)

      @stats = {
        total_scans: scans.count,
        scans_today: today_scans.count,
        verifications: verifications.count,
        verified_today: today_verifications.where(status: "verified").count,
        diaspora_verifications: verifications.where("data->>'channel' = ?", "diaspora").count,
        consent_grants: @partner.consent_grants.count
      }

      @recent_scans = scans
                        .includes(identity_submission: :user)
                        .order(created_at: :desc)
                        .limit(10)

      @api_stats = {
        total: @partner.api_access_logs.count,
        today: @partner.api_access_logs.where("created_at >= ?", Time.current.beginning_of_day).count
      }
    end

    # ============================================================
    # ONACA (Office National du Cadastre) Dashboard Data
    # ============================================================
    def load_onaca_dashboard_data
      @partner = @current_partner

      properties = @partner.verification_records.where(record_type: "property")
      transactions = @partner.verification_records.where(record_type: "land_transaction")
      today_properties = properties.where("created_at >= ?", Time.current.beginning_of_day)

      @stats = {
        total_properties: properties.count,
        properties_today: today_properties.count,
        total_transactions: transactions.count,
        verified: properties.where(status: "verified").count,
        pending: properties.where(status: "pending").count,
        total_scans: @partner.qr_scans.count
      }

      @recent_properties = properties
                             .includes(:user)
                             .order(created_at: :desc)
                             .limit(10)

      @api_stats = {
        total: @partner.api_access_logs.count,
        today: @partner.api_access_logs.where("created_at >= ?", Time.current.beginning_of_day).count
      }
    end

    # ============================================================
    # Banking (BonBank) Dashboard Data
    # ============================================================
    def load_banking_dashboard_data
      @partner = @current_partner

      scans = @partner.qr_scans
      today_scans = scans.where("created_at >= ?", Time.current.beginning_of_day)
      verifications = @partner.verification_records
      today_verifications = verifications.where("created_at >= ?", Time.current.beginning_of_day)

      @stats = {
        total_scans: scans.count,
        scans_today: today_scans.count,
        verifications: verifications.count,
        verified_today: today_verifications.where(status: "verified").count,
        team_members: @partner.users.count,
        consent_grants: @partner.consent_grants.count
      }

      @recent_scans = scans
                        .includes(identity_submission: :user)
                        .order(created_at: :desc)
                        .limit(10)

      @api_stats = {
        total: @partner.api_access_logs.count,
        today: @partner.api_access_logs.where("created_at >= ?", Time.current.beginning_of_day).count
      }
    end

    # ============================================================
    # Shared: Submissions data (loaded for every sector dashboard)
    # ============================================================
    def load_submissions_data
      all_subs = @current_partner.service_applications
                   .includes(:citizen, :partner_schema)
                   .where.not(status: "draft")

      @sub_category = params[:category].presence
      @submissions = all_subs.order(created_at: :desc)

      if @sub_category.present?
        schema_ids = @current_partner.partner_schemas.where(service_category: @sub_category).pluck(:id)
        @submissions = @submissions.where(partner_schema_id: schema_ids)
      end

      # Status filter
      if params[:sub_status].present? && ServiceApplication::STATUSES.include?(params[:sub_status])
        @submissions = @submissions.where(status: params[:sub_status])
      end

      # Date range filter
      if params[:date_from].present?
        @submissions = @submissions.where("service_applications.submitted_at >= ?", Date.parse(params[:date_from]).beginning_of_day)
      end
      if params[:date_to].present?
        @submissions = @submissions.where("service_applications.submitted_at <= ?", Date.parse(params[:date_to]).end_of_day)
      end

      # Service filter
      if params[:service_id].present?
        @submissions = @submissions.where(partner_schema_id: params[:service_id])
      end

      # Search
      if params[:sub_q].present?
        q = "%#{params[:sub_q]}%"
        @submissions = @submissions.joins(:citizen).where(
          "service_applications.verification_code ILIKE :q OR users.first_name ILIKE :q OR users.last_name ILIKE :q",
          q: q
        )
      end

      # Category counts
      @sub_category_counts = {
        total: all_subs.count,
        application: count_subs_by_category(all_subs, "application"),
        transaction: count_subs_by_category(all_subs, "transaction"),
        appointment: count_subs_by_category(all_subs, "appointment"),
        survey: count_subs_by_category(all_subs, "survey")
      }

      # Status counts
      scope = @sub_category.present? ? @submissions.unscope(:order).unscope(where: :status) : all_subs
      @sub_status_counts = scope.group(:status).count

      # Pulse metrics (top metric bar) — dynamic per category
      build_pulse_metrics(all_subs)

      # Type-specific stats
      build_submission_type_stats

      # Active services grouped by category (for quick action cards)
      @sub_active_services = @current_partner.partner_schemas
                               .citizen_services
                               .where(schema_status: "published")
                               .order(:name)

      # Services for filter dropdown
      @sub_services = @current_partner.partner_schemas.citizen_services.order(:name)

      @submissions = @submissions.limit(20)
    end

    def count_subs_by_category(scope, category)
      ids = @current_partner.partner_schemas.where(service_category: category).pluck(:id)
      return 0 if ids.empty?
      scope.where(partner_schema_id: ids).count
    end

    def build_pulse_metrics(all_subs)
      today = Date.current

      # Default pulse (shown when no category selected)
      @sub_pulse = {
        total: all_subs.count,
        today: all_subs.where("submitted_at >= ?", today.beginning_of_day).count,
        pending: all_subs.where(status: %w[submitted under_review]).count,
        approved: all_subs.where(status: "approved").count
      }

      case @sub_category
      when "application"
        app_ids = @current_partner.partner_schemas.where(service_category: "application").pluck(:id)
        app_subs = all_subs.where(partner_schema_id: app_ids)
        @sub_pulse = {
          pending_review: app_subs.where(status: %w[submitted under_review]).count,
          approved_today: app_subs.where(status: "approved")
                           .where("reviewed_at >= ?", today.beginning_of_day).count,
          rejected: app_subs.where(status: "rejected").count,
          total: app_subs.count
        }
      when "transaction"
        tx_ids = @current_partner.partner_schemas.where(service_category: "transaction").pluck(:id)
        tx_subs = all_subs.where(partner_schema_id: tx_ids)
        paid = tx_subs.where.not(total_price_cents: [ nil, 0 ])
        currency = @current_partner.partner_schemas
                     .where(service_category: "transaction")
                     .pick(:currency) || "HTG"
        @sub_pulse = {
          total_revenue: paid.sum(:total_price_cents),
          tickets_sold: paid.count,
          checked_in: tx_subs.where.not(checked_in_at: nil).count,
          currency: currency
        }
      when "appointment"
        apt_ids = @current_partner.partner_schemas.where(service_category: "appointment").pluck(:id)
        apt_subs = all_subs.where(partner_schema_id: apt_ids)
        @sub_pulse = {
          today_booked: apt_subs.where("form_data->>'appointment_date' = ?", today.to_s).count,
          upcoming: apt_subs.where("form_data->>'appointment_date' > ?", today.to_s).count,
          checked_in: apt_subs.where.not(checked_in_at: nil).count,
          no_show: apt_subs.where(checked_in_at: nil)
                     .where("form_data->>'appointment_date' < ?", today.to_s)
                     .where(status: "submitted").count
        }
      when "survey"
        srv_ids = @current_partner.partner_schemas.where(service_category: "survey").pluck(:id)
        srv_subs = all_subs.where(partner_schema_id: srv_ids)
        total = srv_subs.count
        completed = srv_subs.where(status: "submitted").count
        @sub_pulse = {
          total_responses: total,
          this_week: srv_subs.where("submitted_at >= ?", 1.week.ago).count,
          completion_rate: total > 0 ? ((completed.to_f / total) * 100).round(0) : 0
        }
      end
    end

    def build_submission_type_stats
      case @sub_category
      when "transaction"
        paid = @submissions.unscope(:order, :limit).where.not(total_price_cents: [ nil, 0 ])
        @sub_tx_stats = {
          total_revenue: paid.sum(:total_price_cents),
          total_sold: paid.count,
          checked_in: @submissions.unscope(:order, :limit).where.not(checked_in_at: nil).count,
          currency: @current_partner.partner_schemas
                      .where(service_category: "transaction")
                      .pick(:currency) || "HTG"
        }
      when "appointment"
        today = Date.current
        all = @submissions.unscope(:order, :limit)
        @sub_apt_stats = {
          today: all.joins(:partner_schema).where("form_data->>'appointment_date' = ?", today.to_s).count,
          upcoming: all.joins(:partner_schema).where("form_data->>'appointment_date' >= ?", today.to_s).count,
          checked_in: all.where.not(checked_in_at: nil).count,
          no_show: all.where(checked_in_at: nil)
                      .joins(:partner_schema)
                      .where("form_data->>'appointment_date' < ?", today.to_s)
                      .where(status: "submitted").count
        }
      when "survey"
        all = @submissions.unscope(:order, :limit)
        @sub_survey_stats = {
          total_responses: all.count,
          this_week: all.where("submitted_at >= ?", 1.week.ago).count
        }
        @sub_survey_aggregations = build_sub_survey_aggregations
      end
    end

    def build_sub_survey_aggregations
      schema_ids = @current_partner.partner_schemas.where(service_category: "survey").pluck(:id)
      submissions = @current_partner.service_applications
                      .where(partner_schema_id: schema_ids)
                      .where.not(status: "draft")

      return [] if submissions.empty?

      sample = submissions.order(created_at: :desc).first
      fields = sample.frozen_fields.select { |f| %w[radio select multi_checkbox].include?(f["type"]) }

      fields.map do |field|
        key = field["key"]
        options = Array(field["options"]).map { |o| o.is_a?(Hash) ? o["label"] : o }
        counts = Hash.new(0)

        submissions.find_each do |sub|
          val = sub.form_data&.dig(key)
          next if val.blank?
          if val.is_a?(Array)
            val.each { |v| counts[v] += 1 }
          else
            counts[val] += 1
          end
        end

        total = counts.values.sum
        {
          label: field["label"],
          key: key,
          options: options.map { |opt| { label: opt, count: counts[opt], pct: total > 0 ? (counts[opt] * 100.0 / total).round(1) : 0 } }
        }
      end
    end

    def profile_incomplete?
      # Required fields for profile completion
      @current_partner.description.blank? ||
        @current_partner.contact_person.blank? ||
        @current_partner.phone_number.blank?
    end
  end
end
