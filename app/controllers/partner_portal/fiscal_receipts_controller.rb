# frozen_string_literal: true

# 🇭🇹 BonID — Partner Portal: Fiscal Receipts Controller
# =========================================================
# DGI cashier flow: look up a citizen by BonID, create a fiscal receipt,
# and view/search all receipts issued by this partner.
# =========================================================

module PartnerPortal
  class FiscalReceiptsController < PartnerPortal::BaseController
    before_action :set_partner
    before_action :find_receipt, only: %i[show receipt]

    # ============================================================
    # GET /partner_portal/fiscal_receipts
    # ============================================================
    def index
      @receipts = @partner.verification_records
                    .where(record_type: "fiscal_receipt")
                    .order(created_at: :desc)

      # Filters
      if params[:tax_type].present?
        @receipts = @receipts.where("data->'receipt'->>'tax_type' = ?", params[:tax_type])
      end

      if params[:status].present?
        @receipts = @receipts.where(status: params[:status])
      end

      if params[:search].present?
        search = "%#{params[:search]}%"
        @receipts = @receipts.where(
          "data->'receipt'->>'receipt_number' ILIKE :q OR data->'payer'->>'name' ILIKE :q OR data->'payer'->>'bonid' ILIKE :q",
          q: search
        )
      end

      if params[:date_from].present?
        @receipts = @receipts.where("created_at >= ?", Date.parse(params[:date_from]).beginning_of_day)
      end

      if params[:date_to].present?
        @receipts = @receipts.where("created_at <= ?", Date.parse(params[:date_to]).end_of_day)
      end

      @receipts = @receipts.page(params[:page]).per(20)

      # Summary stats
      all_fiscal = @partner.verification_records.where(record_type: "fiscal_receipt")
      @stats = {
        total: all_fiscal.count,
        today: all_fiscal.where("created_at >= ?", Time.current.beginning_of_day).count,
        verified: all_fiscal.where(status: "verified").count,
        consumed: all_fiscal.where("data->'consumption'->>'consumed' = ?", "true").count,
        revenue_htg: all_fiscal.sum { |r| r.data.dig("receipt", "amount_htg").to_i }
      }
    end

    # ============================================================
    # GET /partner_portal/fiscal_receipts/new
    # ============================================================
    def new
      @tax_types = RecordSchemas::FiscalReceiptSchema::VALID_TAX_TYPES
      @payment_methods = RecordSchemas::FiscalReceiptSchema::VALID_PAYMENT_METHODS
      @citizen = nil

      # If BonID provided (from lookup step), find citizen
      if params[:bonid].present?
        @citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase)
        unless @citizen
          flash.now[:alert] = "No citizen found with BonID: #{params[:bonid]}"
        end
      end
    end

    # ============================================================
    # POST /partner_portal/fiscal_receipts
    # ============================================================
    def create
      # BonID is required — receipt must be tied to a verified citizen
      if params[:bonid].blank?
        flash[:alert] = "BonID obligatwa. Ou dwe idantifye kontribyab la anvan kreye yon kes."
        return redirect_to new_partner_portal_fiscal_receipt_path
      end

      citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase)
      unless citizen
        flash[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}"
        return redirect_to new_partner_portal_fiscal_receipt_path
      end

      # Generate receipt number: DGI-YYYY-OFFICE-RANDOM
      office_code = params[:dgi_office_code].to_s.strip.presence || "PAP"
      random = SecureRandom.hex(5).upcase
      receipt_number = "DGI-#{Time.current.year}-#{office_code}-#{random}"

      fiscal_year = params[:fiscal_year].presence || "#{Time.current.year}-#{Time.current.year + 1}"

      record = @partner.verification_records.build(
        record_type: "fiscal_receipt",
        user: citizen,
        status: "verified",
        verified_at: Time.current,
        data: {
          "receipt" => {
            "receipt_number"  => receipt_number,
            "tax_type"        => params[:tax_type],
            "amount_htg"      => params[:amount_htg].to_i,
            "payment_date"    => params[:payment_date].presence || Time.current.strftime("%Y-%m-%d"),
            "dgi_office_code" => office_code,
            "fiscal_year"     => fiscal_year,
            "payment_method"  => params[:payment_method],
            "cashier_id"      => current_partner_admin&.id.to_s
          },
          "payer" => {
            "name"  => citizen&.full_name || params[:payer_name],
            "nif"   => params[:payer_nif],
            "bonid" => citizen&.bonid || params[:bonid]
          },
          "consumption" => {
            "consumed" => false
          },
          "documents" => []
        }
      )

      if record.save
        redirect_to partner_portal_fiscal_receipt_path(record),
                    notice: "Kes fiskal #{receipt_number} kreye avèk siksè."
      else
        flash[:alert] = record.errors.full_messages.join(", ")
        redirect_to new_partner_portal_fiscal_receipt_path(bonid: params[:bonid])
      end
    end

    # ============================================================
    # GET /partner_portal/fiscal_receipts/:id
    # ============================================================
    def show
      # @record set by before_action
    end

    # ============================================================
    # GET /partner_portal/fiscal_receipts/:id/receipt
    # Printable receipt view
    # ============================================================
    def receipt
      render layout: false
    end

    private

    def set_partner
      @partner = @current_partner
    end

    def find_receipt
      @record = @partner.verification_records
                  .where(record_type: "fiscal_receipt")
                  .find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_fiscal_receipts_path,
                  alert: "Kes fiskal pa jwenn."
    end
  end
end
