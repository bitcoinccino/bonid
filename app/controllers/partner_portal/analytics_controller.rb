# app/controllers/partner_portal/analytics_controller.rb
module PartnerPortal
  class AnalyticsController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!
    before_action :set_partner

    def index
      @view = params[:view]
      @has_fiscal_receipts = @partner.verification_records.where(record_type: "fiscal_receipt").exists?

      case @view
      when "fiscal"
        load_fiscal_analytics
      when "payments"
        load_payment_analytics
      when "reconciliation"
        load_reconciliation_data
      else
        load_api_analytics
      end

      respond_to do |format|
        format.html
        format.json { render json: analytics_json }
      end
    end

    private

    def set_partner
      @partner = current_partner_admin.partner
    end

    def load_api_analytics
      @total_requests   = @partner.api_access_logs.count
      @successful_calls = @partner.api_access_logs.where(success: true).count
      @throttled_calls  = @partner.api_access_logs.where(success: false).count

      @calls_by_endpoint = @partner.api_access_logs
        .group(:endpoint)
        .count
        .sort_by { |_endpoint, count| -count }
        .to_h

      @calls_by_day = @partner.api_access_logs
        .where("created_at >= ?", 14.days.ago)
        .group("DATE(created_at)")
        .order("DATE(created_at)")
        .count
    end

    def load_fiscal_analytics
      fiscal = @partner.verification_records.where(record_type: "fiscal_receipt")

      @fiscal_stats = {
        total_receipts: fiscal.count,
        total_revenue_htg: fiscal.sum { |r| r.data.dig("receipt", "amount_htg").to_i },
        consumed_count: fiscal.where("data->'consumption'->>'consumed' = ?", "true").count,
        available_count: fiscal.where(status: "verified")
                               .where("data->'consumption'->>'consumed' != ? OR data->'consumption'->>'consumed' IS NULL", "true")
                               .count,
        avg_receipt_htg: fiscal.count > 0 ? (fiscal.sum { |r| r.data.dig("receipt", "amount_htg").to_i } / fiscal.count) : 0
      }

      # Revenue by tax type (with Creole labels for charts)
      tax_labels = RecordSchemas::FiscalReceiptSchema::TAX_TYPE_LABELS
      @revenue_by_tax_type = {}
      @count_by_tax_type = {}
      fiscal.find_each do |r|
        tax = r.data.dig("receipt", "tax_type") || "other"
        label = tax_labels[tax] || tax.titleize
        @revenue_by_tax_type[label] ||= 0
        @revenue_by_tax_type[label] += r.data.dig("receipt", "amount_htg").to_i
        @count_by_tax_type[label] ||= 0
        @count_by_tax_type[label] += 1
      end
      @revenue_by_tax_type = @revenue_by_tax_type.sort_by { |_, v| -v }.to_h
      @count_by_tax_type = @count_by_tax_type.sort_by { |_, v| -v }.to_h

      # ── Time Series ──
      # Daily (last 30 days)
      @receipts_daily = fiscal
        .where("created_at >= ?", 30.days.ago)
        .group("DATE(created_at)")
        .order("DATE(created_at)")
        .count

      @revenue_daily = {}
      fiscal.where("created_at >= ?", 30.days.ago).find_each do |r|
        day = r.created_at.to_date.to_s
        @revenue_daily[day] ||= 0
        @revenue_daily[day] += r.data.dig("receipt", "amount_htg").to_i
      end

      # Weekly (last 12 weeks)
      @receipts_weekly = fiscal
        .where("created_at >= ?", 12.weeks.ago)
        .group(Arel.sql("DATE_TRUNC('week', created_at)"))
        .order(Arel.sql("DATE_TRUNC('week', created_at)"))
        .count
        .transform_keys { |k| k.to_date.strftime("%d %b") }

      # Monthly (last 12 months)
      @receipts_monthly = fiscal
        .where("created_at >= ?", 12.months.ago)
        .group(Arel.sql("DATE_TRUNC('month', created_at)"))
        .order(Arel.sql("DATE_TRUNC('month', created_at)"))
        .count
        .transform_keys { |k| k.to_date.strftime("%b %Y") }

      @revenue_monthly = {}
      fiscal.where("created_at >= ?", 12.months.ago).find_each do |r|
        month = r.created_at.strftime("%b %Y")
        @revenue_monthly[month] ||= 0
        @revenue_monthly[month] += r.data.dig("receipt", "amount_htg").to_i
      end

      # Yearly
      @receipts_yearly = fiscal
        .group(Arel.sql("DATE_TRUNC('year', created_at)"))
        .order(Arel.sql("DATE_TRUNC('year', created_at)"))
        .count
        .transform_keys { |k| k.to_date.year.to_s }

      # ── Geographic: By DGI Office (department proxy) ──
      @receipts_by_office = {}
      @revenue_by_office = {}
      fiscal.find_each do |r|
        office = r.data.dig("receipt", "dgi_office_code") || "N/A"
        @receipts_by_office[office] ||= 0
        @receipts_by_office[office] += 1
        @revenue_by_office[office] ||= 0
        @revenue_by_office[office] += r.data.dig("receipt", "amount_htg").to_i
      end
      @receipts_by_office = @receipts_by_office.sort_by { |_, v| -v }.to_h
      @revenue_by_office = @revenue_by_office.sort_by { |_, v| -v }.to_h

      # ── By Citizen Department (from user address if available) ──
      @receipts_by_department = {}
      fiscal.includes(:user).find_each do |r|
        dept = r.user&.department || "Enkonni"
        @receipts_by_department[dept] ||= 0
        @receipts_by_department[dept] += 1
      end
      @receipts_by_department = @receipts_by_department.sort_by { |_, v| -v }.to_h

      # ── By Citizen Commune ──
      @receipts_by_commune = {}
      fiscal.includes(:user).find_each do |r|
        commune = r.user&.commune || "Enkonni"
        @receipts_by_commune[commune] ||= 0
        @receipts_by_commune[commune] += 1
      end
      @receipts_by_commune = @receipts_by_commune.sort_by { |_, v| -v }.first(15).to_h

      # ── Payment Method Breakdown ──
      method_labels = RecordSchemas::FiscalReceiptSchema::PAYMENT_METHOD_LABELS
      @receipts_by_payment_method = {}
      fiscal.find_each do |r|
        method = r.data.dig("receipt", "payment_method") || "cash"
        label = method_labels[method] || method.titleize
        @receipts_by_payment_method[label] ||= 0
        @receipts_by_payment_method[label] += 1
      end

      # ── Paid vs Consumed (for bar comparison) ──
      @paid_vs_consumed = {
        "Kreye (Peye)" => fiscal.count,
        "Konsome" => fiscal.where("data->'consumption'->>'consumed' = ?", "true").count,
        "Disponib" => fiscal.where(status: "verified")
                            .where("data->'consumption'->>'consumed' != ? OR data->'consumption'->>'consumed' IS NULL", "true")
                            .count
      }

      # Top consuming agencies
      @consuming_agencies = {}
      fiscal.where("data->'consumption'->>'consumed' = ?", "true").find_each do |r|
        agency = r.data.dig("consumption", "consumed_by_agency") || "unknown"
        @consuming_agencies[agency] ||= 0
        @consuming_agencies[agency] += 1
      end
    end

    def load_payment_analytics
      completed = DgiPayment.where(status: "completed")
      all_payments = DgiPayment.all

      @payment_stats = {
        total_payments: all_payments.count,
        completed_payments: completed.count,
        pending_payments: all_payments.where(status: %w[pending pending_cash]).count,
        total_revenue_htg: completed.sum(:amount_htg).to_i + completed.sum(:fee_htg).to_i,
        dgi_revenue_htg: completed.sum(:amount_htg).to_i,
        bonid_fees_htg: completed.sum(:fee_htg).to_i,
        avg_payment_htg: completed.count > 0 ? ((completed.sum(:amount_htg).to_i + completed.sum(:fee_htg).to_i) / completed.count) : 0
      }

      # By payment method
      @payments_by_method = {}
      @revenue_by_method = {}
      completed.find_each do |p|
        method = case p.payment_method
                 when "zellus" then "Zellus"
                 when "cash_window" then "Kach"
                 when "bank_transfer" then "Transfè Bankè"
                 when "moncash" then "MonCash"
                 else p.payment_method&.titleize || "Lòt"
                 end
        @payments_by_method[method] ||= 0
        @payments_by_method[method] += 1
        @revenue_by_method[method] ||= 0
        @revenue_by_method[method] += p.amount_htg.to_i + p.fee_htg.to_i
      end

      # By form type
      @payments_by_form = {}
      @revenue_by_form = {}
      completed.includes(:verification_record).find_each do |p|
        form = p.verification_record&.record_type&.titleize&.gsub("_", " ") || "Lòt"
        @payments_by_form[form] ||= 0
        @payments_by_form[form] += 1
        @revenue_by_form[form] ||= 0
        @revenue_by_form[form] += p.amount_htg.to_i + p.fee_htg.to_i
      end
      @payments_by_form = @payments_by_form.sort_by { |_, v| -v }.to_h
      @revenue_by_form = @revenue_by_form.sort_by { |_, v| -v }.to_h

      # Daily payments (last 30 days)
      @payments_daily = completed
        .where("paid_at >= ?", 30.days.ago)
        .group("DATE(paid_at)")
        .order("DATE(paid_at)")
        .count

      @revenue_daily = {}
      completed.where("paid_at >= ?", 30.days.ago).find_each do |p|
        day = p.paid_at.to_date.to_s
        @revenue_daily[day] ||= 0
        @revenue_daily[day] += p.amount_htg.to_i + p.fee_htg.to_i
      end

      # Monthly payments (last 12 months)
      @payments_monthly = completed
        .where("paid_at >= ?", 12.months.ago)
        .group(Arel.sql("DATE_TRUNC('month', paid_at)"))
        .order(Arel.sql("DATE_TRUNC('month', paid_at)"))
        .count
        .transform_keys { |k| k.to_date.strftime("%b %Y") }

      @revenue_monthly = {}
      completed.where("paid_at >= ?", 12.months.ago).find_each do |p|
        month = p.paid_at.strftime("%b %Y")
        @revenue_monthly[month] ||= 0
        @revenue_monthly[month] += p.amount_htg.to_i + p.fee_htg.to_i
      end

      # Declaration stats
      citizen_forms = %w[nif_registration business_registration patente_declaration tca_declaration ras_ir_declaration fermage]
      declarations = VerificationRecord.where(record_type: citizen_forms).where("data->>'filed_by' = ?", "citizen")
      @declaration_stats = {
        total: declarations.count,
        pending: declarations.where(status: "pending").count,
        verified: declarations.where(status: "verified").count,
        rejected: declarations.where(status: "rejected").count,
        approval_rate: declarations.where(status: %w[verified rejected]).count > 0 ?
          ((declarations.where(status: "verified").count.to_f / declarations.where(status: %w[verified rejected]).count) * 100).round(1) : 0
      }

      @declarations_by_form = declarations.group(:record_type).count
        .transform_keys { |k| k.titleize.gsub("_", " ") }
        .sort_by { |_, v| -v }.to_h
    end

    def load_reconciliation_data
      fiscal = @partner.verification_records.where(record_type: "fiscal_receipt")

      @reconciliation = {
        total_issued: fiscal.count,
        total_consumed: fiscal.where("data->'consumption'->>'consumed' = ?", "true").count,
        total_available: fiscal.where(status: "verified")
                               .where("data->'consumption'->>'consumed' != ? OR data->'consumption'->>'consumed' IS NULL", "true")
                               .count,
        total_revenue_htg: fiscal.sum { |r| r.data.dig("receipt", "amount_htg").to_i },
        consumed_revenue_htg: fiscal.where("data->'consumption'->>'consumed' = ?", "true")
                                    .sum { |r| r.data.dig("receipt", "amount_htg").to_i }
      }

      @reconciliation[:available_revenue_htg] = @reconciliation[:total_revenue_htg] - @reconciliation[:consumed_revenue_htg]
      @reconciliation[:consumption_rate] = if @reconciliation[:total_issued] > 0
        ((@reconciliation[:total_consumed].to_f / @reconciliation[:total_issued]) * 100).round(1)
      else
        0
      end
    end

    def analytics_json
      case @view
      when "fiscal"
        { fiscal_stats: @fiscal_stats, revenue_by_tax_type: @revenue_by_tax_type, receipts_by_day: @receipts_by_day }
      when "payments"
        { payment_stats: @payment_stats, declaration_stats: @declaration_stats }
      when "reconciliation"
        { reconciliation: @reconciliation }
      else
        {
          total_requests: @total_requests,
          successful_calls: @successful_calls,
          throttled_calls: @throttled_calls,
          calls_by_endpoint: @calls_by_endpoint,
          calls_by_day: @calls_by_day
        }
      end
    end
  end
end
