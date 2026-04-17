# frozen_string_literal: true

module PartnerPortal
  class SubmissionsController < BaseController
    before_action :set_submission, only: [ :show, :approve, :reject, :add_note, :check_in ]

    # GET /partner_portal/submissions
    def index
      @submissions = @current_partner.service_applications
                       .includes(:citizen, :partner_schema)
                       .where.not(status: "draft")
                       .order(created_at: :desc)

      # ── Category filter (drives view mode) ──
      @category = params[:category].presence
      if @category.present?
        schema_ids = @current_partner.partner_schemas.where(service_category: @category).pluck(:id)
        @submissions = @submissions.where(partner_schema_id: schema_ids)
      end

      # Filter by status
      if params[:status].present? && ServiceApplication::STATUSES.include?(params[:status])
        @submissions = @submissions.where(status: params[:status])
      end

      # Filter by service
      if params[:service_id].present?
        @submissions = @submissions.where(partner_schema_id: params[:service_id])
      end

      # Search by verification code or citizen name
      if params[:q].present?
        q = "%#{params[:q]}%"
        @submissions = @submissions.joins(:citizen).where(
          "service_applications.verification_code ILIKE :q OR users.first_name ILIKE :q OR users.last_name ILIKE :q",
          q: q
        )
      end

      # ── Type-specific stats ──
      build_type_stats

      # For filter dropdowns
      @services = @current_partner.partner_schemas.citizen_services.order(:name)
      scope = @category.present? ? @submissions.unscope(where: :status) : @current_partner.service_applications.where.not(status: "draft")
      @status_counts = scope.group(:status).count

      # Category counts for tabs
      all_subs = @current_partner.service_applications.where.not(status: "draft")
      @category_counts = {
        total: all_subs.count,
        application: count_by_category(all_subs, "application"),
        transaction: count_by_category(all_subs, "transaction"),
        appointment: count_by_category(all_subs, "appointment"),
        survey: count_by_category(all_subs, "survey")
      }

      @submissions = @submissions.page(params[:page]).per(20) if @submissions.respond_to?(:page)
    end

    # GET /partner_portal/submissions/:id
    def show
      @fields = @submission.frozen_fields
      @form_data = @submission.form_data || {}
      @notes = @submission.staff_notes || []
      @service_category = @submission.partner_schema.service_category
    end

    # PATCH /partner_portal/submissions/:id/approve
    def approve
      @submission.approve!(@current_portal_user)
      redirect_to partner_portal_submission_path(@submission),
                  notice: "Aplikasyon apwouve avèk siksè."
    rescue => e
      redirect_to partner_portal_submission_path(@submission),
                  alert: "Erè: #{e.message}"
    end

    # PATCH /partner_portal/submissions/:id/reject
    def reject
      reason = params[:rejection_reason].presence || "Pa gen rezon espesifye."
      @submission.reject!(@current_portal_user, reason: reason)
      redirect_to partner_portal_submission_path(@submission),
                  notice: "Aplikasyon rejte. Sitwayen an ap resevwa notifikasyon."
    rescue => e
      redirect_to partner_portal_submission_path(@submission),
                  alert: "Erè: #{e.message}"
    end

    # PATCH /partner_portal/submissions/:id/check_in
    def check_in
      if @submission.checked_in_at.present?
        redirect_to partner_portal_submission_path(@submission),
                    alert: "Deja tcheke."
        return
      end

      @submission.update!(checked_in_at: Time.current)
      redirect_to partner_portal_submission_path(@submission),
                  notice: "Tcheke avèk siksè!"
    rescue => e
      redirect_to partner_portal_submission_path(@submission),
                  alert: "Erè: #{e.message}"
    end

    # POST /partner_portal/submissions/:id/add_note
    def add_note
      note_text = params[:note].to_s.strip
      return redirect_to(partner_portal_submission_path(@submission), alert: "Nòt vid.") if note_text.blank?

      notes = @submission.staff_notes || []
      notes << {
        text: note_text,
        author_id: @current_portal_user.id,
        author_name: @current_portal_user.email,
        created_at: Time.current.iso8601
      }

      @submission.update!(staff_notes: notes)
      redirect_to partner_portal_submission_path(@submission),
                  notice: "Nòt ajoute."
    end

    # ============================================================
    # AGENT FORM — Fill service on behalf of citizen
    # GET /partner_portal/submissions/agent_form?citizen_id=X&schema_id=Y
    # ============================================================
    def agent_form
      @citizen = User.find(params[:citizen_id])
      @schema = @current_partner.partner_schemas.find(params[:schema_id])
      @partner = @current_partner

      # Reuse existing draft or create a new one
      @application = ServiceApplication
                       .where(citizen: @citizen, partner: @partner, partner_schema: @schema, status: "draft")
                       .order(updated_at: :desc)
                       .first

      unless @application
        @application = ServiceApplication.create!(
          citizen: @citizen,
          partner: @partner,
          partner_schema: @schema,
          status: "draft",
          form_data: {},
          calculated_values: {}
        )
      end

      prepare_agent_form
    end

    # POST /partner_portal/submissions/agent_create
    def agent_create
      @citizen = User.find(params[:citizen_id])
      @schema = @current_partner.partner_schemas.find(params[:schema_id])
      @application = @current_partner.service_applications.find(params[:application_id])

      unless @application.draft?
        redirect_to partner_portal_submission_path(@application), alert: "Aplikasyon sa a deja soumèt."
        return
      end

      merged_data = (@application.form_data || {}).merge(agent_form_data)

      # Validate required fields
      missing = validate_agent_required_fields(merged_data)
      if missing.any?
        @application.update!(form_data: merged_data)
        @partner = @current_partner
        prepare_agent_form
        flash.now[:alert] = "Tanpri ranpli tout chan obligatwa: #{missing.join(', ')}"
        render :agent_form, status: :unprocessable_entity
        return
      end

      # Compute pricing
      price_attrs = compute_agent_pricing(merged_data)

      @application.update!(
        form_data: merged_data,
        status: "submitted",
        submitted_at: Time.current,
        **price_attrs
      )

      redirect_to partner_portal_submission_path(@application),
                  notice: "Sèvis kreye avèk siksè pou #{@citizen.full_name}."
    end

    # PATCH /partner_portal/submissions/agent_update
    def agent_update
      @application = @current_partner.service_applications.find(params[:application_id])

      unless @application.draft?
        redirect_to partner_portal_submission_path(@application), alert: "Aplikasyon sa a deja soumèt."
        return
      end

      merged_data = (@application.form_data || {}).merge(agent_form_data)
      @application.update!(form_data: merged_data)

      if params[:next_step].present?
        redirect_to agent_form_partner_portal_submissions_path(
          citizen_id: @application.citizen_id,
          schema_id: @application.partner_schema_id,
          step: params[:next_step]
        )
      else
        redirect_to agent_form_partner_portal_submissions_path(
          citizen_id: @application.citizen_id,
          schema_id: @application.partner_schema_id
        ), notice: "Done sove."
      end
    end

    # GET /partner_portal/submissions/export
    def export
      submissions = @current_partner.service_applications
                      .includes(:citizen, :partner_schema)
                      .where.not(status: "draft")

      if params[:category].present?
        schema_ids = @current_partner.partner_schemas.where(service_category: params[:category]).pluck(:id)
        submissions = submissions.where(partner_schema_id: schema_ids)
      end

      if params[:service_id].present?
        submissions = submissions.where(partner_schema_id: params[:service_id])
      end

      csv_data = generate_csv(submissions.order(created_at: :desc))
      send_data csv_data,
                filename: "soumisyon-#{Date.current}.csv",
                type: "text/csv; charset=utf-8"
    end

    private

    def set_submission
      @submission = @current_partner.service_applications.find(params[:id])
    end

    def count_by_category(scope, category)
      ids = @current_partner.partner_schemas.where(service_category: category).pluck(:id)
      return 0 if ids.empty?
      scope.where(partner_schema_id: ids).count
    end

    def build_type_stats
      case @category
      when "transaction"
        paid = @submissions.unscope(:order).where.not(total_price_cents: [ nil, 0 ])
        @tx_stats = {
          total_revenue: paid.sum(:total_price_cents),
          total_sold: paid.count,
          checked_in: @submissions.unscope(:order).where.not(checked_in_at: nil).count,
          currency: @current_partner.partner_schemas
                      .where(service_category: "transaction")
                      .pick(:currency) || "HTG"
        }
      when "appointment"
        today = Date.current
        all = @submissions.unscope(:order)
        @apt_stats = {
          today: all.joins(:partner_schema).where("form_data->>'appointment_date' = ?", today.to_s).count,
          upcoming: all.joins(:partner_schema).where("form_data->>'appointment_date' >= ?", today.to_s).count,
          checked_in: all.where.not(checked_in_at: nil).count,
          no_show: all.where(checked_in_at: nil)
                      .joins(:partner_schema)
                      .where("form_data->>'appointment_date' < ?", today.to_s)
                      .where(status: "submitted").count
        }
      when "survey"
        all = @submissions.unscope(:order)
        @survey_stats = {
          total_responses: all.count,
          this_week: all.where("submitted_at >= ?", 1.week.ago).count
        }
        # Build aggregated analytics for radio/select/multi_checkbox fields
        @survey_aggregations = build_survey_aggregations
      end
    end

    def build_survey_aggregations
      # Get all submissions for survey schemas
      schema_ids = @current_partner.partner_schemas.where(service_category: "survey").pluck(:id)
      submissions = @current_partner.service_applications
                      .where(partner_schema_id: schema_ids)
                      .where.not(status: "draft")

      return [] if submissions.empty?

      # Use the most recent schema's fields as reference
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

    def generate_csv(submissions)
      require "csv"
      CSV.generate(headers: true, col_sep: ",") do |csv|
        csv << [ "Kòd", "Sitwayen", "Sèvis", "Kategori", "Estati", "Pri", "Soumèt", "Tcheke" ]

        submissions.each do |sub|
          csv << [
            sub.verification_code,
            "#{sub.citizen.last_name} #{sub.citizen.first_name}",
            sub.partner_schema.name,
            sub.partner_schema.service_category,
            sub.status_label,
            sub.price_display,
            sub.submitted_at&.strftime("%d/%m/%Y %H:%M"),
            sub.checked_in_at&.strftime("%d/%m/%Y %H:%M")
          ]
        end
      end
    end

    # ── Agent Form Helpers ──

    def prepare_agent_form
      @fields_by_step = @application.frozen_fields_by_step
      @current_step = (params[:step] || 0).to_i
      @total_steps = @fields_by_step.length
      @saved_data = @application.form_data || {}

      # Auto-fill from citizen's BonID profile
      addr = @citizen.try(:address)
      @auto_fill = {
        "first_name" => @citizen.first_name,
        "last_name" => @citizen.last_name,
        "email" => @citizen.email,
        "phone" => @citizen.phone,
        "bonid" => @citizen.try(:bonid),
        "date_of_birth" => @citizen.try(:date_of_birth)&.strftime("%Y-%m-%d"),
        "street_address" => @citizen.try(:street_address) || addr&.street_address,
        "locality" => addr&.locality,
        "commune" => addr&.commune&.name,
        "department" => addr&.department&.name,
        "department_id" => addr&.department_id,
        "commune_id" => addr&.commune_id
      }.compact
    end

    def agent_form_data
      (params[:form_data] || {}).to_unsafe_h.transform_values do |v|
        case v
        when String then v.strip
        when Hash
          v.sort_by { |k, _| k.to_i }.map do |_, row|
            next unless row.is_a?(Hash)
            row.transform_values { |rv| rv.is_a?(String) ? rv.strip : rv }
          end.compact
        else v
        end
      end
    end

    def validate_agent_required_fields(data)
      missing = []
      @application.frozen_fields.each do |field|
        next unless field["required"]
        next if field["type"].in?(%w[bonid_signature seal_placeholder calculated section instructional_text])
        next if field["filled_by"] == "partner"

        if field["type"] == "address"
          missing << (field["label"] || field["key"]) if data["#{field['key']}_department"].blank?
          next
        end

        missing << (field["label"] || field["key"]) if data[field["key"]].blank?
      end
      missing
    end

    def compute_agent_pricing(data)
      schema = @application.partner_schema
      currency = schema.currency || "HTG"
      base_cents = schema.price_cents.to_i

      case schema.pricing_type
      when "free"
        { total_price_cents: 0, currency: currency, price_snapshot: { base: 0, total: 0, currency: currency } }
      when "variable"
        { total_price_cents: base_cents, currency: currency, price_snapshot: { base: base_cents, total: base_cents, currency: currency } }
      else
        # Fixed pricing — use base + mandatory fees
        total = schema.total_price_in_cents
        {
          total_price_cents: total,
          currency: currency,
          price_snapshot: {
            base_cents: base_cents,
            total_cents: total,
            currency: currency,
            frozen_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
