# frozen_string_literal: true

# PartnerPortal::DgiReviewController — Review Queue for Citizen-Filed Declarations
# ===================================================================================
# DGI partners see all citizen-filed (pending) declarations and can:
#   - Review data side-by-side with BonID verified profile
#   - Approve → status becomes "verified"
#   - Return → status becomes "rejected" with reason
# ===================================================================================

module PartnerPortal
  class DgiReviewController < PartnerPortal::BaseController
    include DgiRejectionReasons

    before_action :set_partner
    before_action :find_record, only: [ :show, :approve, :reject ]

    REVIEWABLE_TYPES = %w[
      nif_registration business_registration
      patente_declaration tca_declaration ras_ir_declaration
      fermage
    ].freeze

    # ============================================================
    # INDEX — Review queue (citizen-filed pending declarations)
    # ============================================================
    def index
      @records = VerificationRecord
                   .where(record_type: REVIEWABLE_TYPES, status: "pending")
                   .where("data->>'filed_by' = ?", "citizen")
                   .order(created_at: :asc) # FIFO

      @records = @records.where(record_type: params[:form_type]) if params[:form_type].present?

      if params[:search].present?
        q = "%#{params[:search]}%"
        @records = @records.where(
          "data->'identification'->>'raison_sociale' ILIKE :q OR " \
          "data->'identification'->>'nif' ILIKE :q OR " \
          "data->'personne'->>'nom' ILIKE :q OR " \
          "data->'personne'->>'prenom' ILIKE :q OR " \
          "data->>'declaration_number' ILIKE :q",
          q: q
        )
      end

      @records = @records.page(params[:page]).per(20)

      @stats = {
        total_pending: VerificationRecord.where(record_type: REVIEWABLE_TYPES, status: "pending")
                         .where("data->>'filed_by' = ?", "citizen").count,
        today: VerificationRecord.where(record_type: REVIEWABLE_TYPES, status: "pending")
                 .where("data->>'filed_by' = ?", "citizen")
                 .where("created_at >= ?", Time.current.beginning_of_day).count,
        resubmissions: VerificationRecord.where(record_type: REVIEWABLE_TYPES, status: "pending")
                         .where("data->>'filed_by' = ?", "citizen")
                         .where("data ? 'resubmissions'").count
      }
    end

    # ============================================================
    # SHOW — Side-by-side review (citizen data vs BonID profile)
    # ============================================================
    def show
      @citizen = @record.user
      @payment = DgiPayment.find_by(verification_record: @record)
    end

    # ============================================================
    # APPROVE — Mark declaration as verified
    # ============================================================
    def approve
      @record.update!(
        status: "verified",
        verified_at: Time.current,
        partner: @partner,
        data: @record.data.merge(
          "reviewed_by"  => current_portal_user&.email,
          "reviewed_at"  => Time.current.iso8601,
          "review_action" => "approved"
        )
      )

      # For NIF registrations, generate the NIF number on approval
      if @record.record_type == "nif_registration" && @record.data["nif_genere"].blank?
        nif = generate_nif_number
        @record.data["nif_genere"] = nif
        @record.save!
      end

      # Notify citizen of approval
      Bongouv::DgiMailer.review_complete(@record, "verified").deliver_later

      redirect_to partner_portal_dgi_review_index_path,
                  notice: "Deklarasyon #{@record.data['declaration_number']} apwouve avèk siksè."
    end

    # ============================================================
    # REJECT — Return to citizen with structured rejection reason
    # ============================================================
    def reject
      code  = params[:rejection_code].to_s.strip
      notes = params[:rejection_notes].to_s.strip

      reason = DgiRejectionReasons::REJECTION_CODES[code]
      if reason.blank?
        return redirect_to partner_portal_dgi_review_path(@record),
                          alert: "Tanpri chwazi yon rezon rejè valid."
      end

      rejection_data = {
        "code"        => code,
        "reason"      => reason,
        "category"    => DgiRejectionReasons.category_for(code),
        "notes"       => notes.presence,
        "rejected_at" => Time.current.iso8601,
        "rejected_by" => current_portal_user&.id || current_portal_user&.email
      }

      @record.update!(
        status: "rejected",
        data: @record.data.merge(
          "rejection"        => rejection_data,
          "rejection_reason" => "#{code}: #{reason}", # backwards-compatible
          "reviewed_by"      => current_portal_user&.email,
          "reviewed_at"      => Time.current.iso8601,
          "review_action"    => "rejected"
        )
      )

      # Notify citizen of rejection
      Bongouv::DgiMailer.review_complete(@record, "rejected").deliver_later

      redirect_to partner_portal_dgi_review_index_path,
                  notice: "Deklarasyon #{@record.data['declaration_number']} retounen ak rezon."
    end

    private

    def set_partner
      @partner = @current_partner
    end

    def find_record
      @record = VerificationRecord.where(record_type: REVIEWABLE_TYPES).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_dgi_review_index_path, alert: "Deklarasyon pa jwenn."
    end

    def generate_nif_number
      # Simple NIF format: NIF-HT-XXXXXXXXX (9 digits)
      loop do
        nif = "NIF-HT-#{rand(100_000_000..999_999_999)}"
        break nif unless VerificationRecord.where("data->>'nif_genere' = ?", nif).exists?
      end
    end
  end
end
