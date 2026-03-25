# frozen_string_literal: true

module Admin
  class PartnersController < Admin::ApplicationController
    before_action :set_partner, only: %i[
      show edit update destroy geocode_address
      resend_verification_email resend_invitation approve reject suspend restore
      soft_delete rotate_api_key regenerate_qr
      send_invite_single send_invite_bulk
    ]

    # ------------------------------------------------------------------
    # INDEX
    # ------------------------------------------------------------------
    def index
      base_scope =
        case params[:filter]
        when "verified"
          Partner.where.not(verified_at: nil)
        when "pending"
          Partner.where(status: "pending")
        when "rejected"
          Partner.where(status: "rejected")
        when "suspended"
          Partner.where(status: "suspended")
        else
          Partner.where(deleted_at: nil) # replaces kept
        end

      if params[:filter] == "deleted"
        base_scope = Partner.where.not(deleted_at: nil) # replaces only_deleted
      end

      base_scope = base_scope.where(sector: params[:sector]) if params[:sector].present?

      @q = base_scope.ransack(params[:q])
      @partners = @q.result
                    .includes(:logo_attachment, :logo_blob)
                    .order(created_at: :desc)
                    .page(params[:page]).per(20)

      @sectors = Partner.distinct.pluck(:sector).compact.sort
    end

    # ------------------------------------------------------------------
    # SHOW / EDIT
    # ------------------------------------------------------------------
    def show; end

    def edit
      @partner.build_address unless @partner.address.present?
    end

    # ------------------------------------------------------------------
    # CREATE
    # ------------------------------------------------------------------
    def create
      @partner = Partner.new(partner_params)
      @partner.admin_user_id = current_admin_user.id

      ActiveRecord::Base.transaction do
        if @partner.save
          PartnerSetupService.new(
            partner: @partner,
            admin_user: current_admin_user
          ).approve!

          PartnerAuditLog.create!(
            partner: @partner,
            admin_user: current_admin_user,
            event: "created",
            details: "Partner manually onboarded + auto-approved."
          )

          redirect_to admin_partner_path(@partner.uuid),
            notice: "✅ Partner “#{@partner.name}” created and approved."
        else
          redirect_to admin_partners_path,
            alert: "⚠️ Failed to create partner: #{@partner.errors.full_messages.to_sentence}"
        end
      end

    rescue => e
      Rails.logger.error("🚨 Admin::PartnersController#create FAILED: #{e.message}")
      redirect_to admin_partners_path, alert: "❌ Unexpected error."
    end

    # ------------------------------------------------------------------
    # UPDATE (Standard update / reject from form)
    # ------------------------------------------------------------------
    def update
      service = PartnerSetupService.new(partner: @partner, admin_user: current_admin_user)

      if params[:commit].to_s.downcase.include?("reject")
        return handle_rejection(service)
      end

      if @partner.update(partner_params)
        redirect_to admin_partner_path(@partner.uuid),
          notice: "✅ Partner updated successfully."
      else
        flash.now[:alert] = "⚠️ Failed to update partner."
        render :edit, status: :unprocessable_entity
      end

    rescue => e
      Rails.logger.error("🚨 Admin::PartnersController#update FAILED: #{e.message}")
      redirect_to admin_partner_path(@partner.uuid),
        alert: "⚠️ Unexpected error."
    end

    # ------------------------------------------------------------------
    # APPROVE / REJECT
    # ------------------------------------------------------------------
    def approve
      service = PartnerSetupService.new(partner: @partner, admin_user: current_admin_user)
      handle_approval(service)
    end

    def reject
      service = PartnerSetupService.new(partner: @partner, admin_user: current_admin_user)
      handle_rejection(service)
    end

    # ------------------------------------------------------------------
    # SUSPEND / RESTORE
    # ------------------------------------------------------------------
    def suspend
      @partner.update!(status: "suspended")

      PartnerAuditLog.log!(@partner, current_admin_user, "suspended")

      redirect_to admin_partner_path(@partner.uuid),
        notice: "⛔ Partner suspended."
    end

    def restore
      @partner.update!(status: "pending", deleted_at: nil)

      PartnerAuditLog.log!(@partner, current_admin_user, "restored")

      redirect_to admin_partner_path(@partner.uuid),
        notice: "🔄 Partner restored."
    end

    # ------------------------------------------------------------------
    # SOFT-DELETE
    # ------------------------------------------------------------------
    def soft_delete
      @partner.update_column(:deleted_at, Time.current)

      PartnerAuditLog.log!(@partner, current_admin_user, "soft_deleted")

      redirect_to admin_partners_path, notice: "🗑️ Partner deleted."
    end

    # ------------------------------------------------------------------
    # ROTATE API KEY
    # ------------------------------------------------------------------
    def rotate_api_key
      PartnerApiKeyRotationService.new(@partner, current_admin_user).rotate!

      PartnerAuditLog.log!(@partner, current_admin_user, "api_key_rotated")

      redirect_to admin_partner_path(@partner.uuid),
        notice: "🔑 API key rotated."
    end

    # ------------------------------------------------------------------
    # REGENERATE QR
    # ------------------------------------------------------------------
    def regenerate_qr
      @partner.generate_qr!

      PartnerAuditLog.log!(@partner, current_admin_user, "qr_regenerated")

      redirect_to admin_partner_path(@partner.uuid),
        notice: "🔄 QR regenerated."
    end



# ------------------------------------------------------------------
# VERIFY EMAIL AGAIN
# ------------------------------------------------------------------
def resend_verification_email
  # Prevent resend if email already verified
  if @partner.email_verified?
    return redirect_to admin_partner_path(@partner.uuid),
      alert: "This partner already verified their email."
  end

  # Regenerate token if missing (edge case: token was cleared)
  if @partner.email_verification_token.blank?
    @partner.generate_email_verification_token
    @partner.save!
  end

  Partners::Mailer.with(partner: @partner).verification_email.deliver_later

  PartnerAuditLog.log!(
    @partner,
    current_admin_user,
    "verification_email_resent",
    email: @partner.email
  )

  redirect_to admin_partner_path(@partner.uuid),
              notice: "Verification email resent successfully."
end


    # ------------------------------------------------------------------
    # RESEND INVITATION (password setup link for approved partners)
    # ------------------------------------------------------------------
    def resend_invitation
      unless @partner.verified_at.present?
        return redirect_to admin_partner_path(@partner.uuid),
          alert: "Partner must be approved before resending an invitation."
      end

      # Find the partner admin user created during approval
      partner_user = @partner.users.with_role(:partner_admin).first ||
                     @partner.officers.first

      unless partner_user
        return redirect_to admin_partner_path(@partner.uuid),
          alert: "No admin account found for this partner. Try approving again."
      end

      # Generate fresh password reset token
      raw, enc = Devise.token_generator.generate(partner_user.class, :reset_password_token)
      partner_user.update!(
        reset_password_token: enc,
        reset_password_sent_at: Time.current
      )

      # Build the password setup URL
      host = Rails.application.routes.default_url_options[:host].presence || "localhost"
      port = Rails.application.routes.default_url_options[:port]
      protocol = Rails.application.routes.default_url_options[:protocol] || "http"

      url_opts = { reset_password_token: raw, host: host, protocol: protocol }
      url_opts[:port] = port if port.present?

      invite_url = if partner_user.is_a?(Officer)
                     edit_officer_password_url(**url_opts)
                   else
                     edit_partner_admin_password_url(**url_opts)
                   end

      Admin::PartnerAdminMailer.invite(
        partner: @partner,
        email: partner_user.email,
        invite_url: invite_url
      ).deliver_later

      PartnerAuditLog.log!(
        @partner,
        current_admin_user,
        "invitation_resent",
        email: partner_user.email
      )

      redirect_to admin_partner_path(@partner.uuid),
        notice: "Invitation resent to #{partner_user.email}."
    end

    # ------------------------------------------------------------------
    # DEVlSE INVITABLE — SINGLE INVITE
    # ------------------------------------------------------------------
    def send_invite_single
      email = params[:email].to_s.strip
      if email.blank?
        return redirect_to invite_single_admin_partner_path(@partner.uuid),
          alert: "⚠️ Email cannot be blank."
      end

      service = SectorInvitationService
      model = service.resolve_user_model_for_sector(@partner.sector)
      role_label = service.invite_role_for_sector(@partner.sector)

      user = model.find_or_initialize_by(email: email)

      if user.new_record?
        user.partner_id = @partner.id if user.respond_to?(:partner_id=)
        user.save!
      end

      user.invite! unless user.invitation_token.present?

      PartnerAuditLog.log!(
        @partner, current_admin_user, "invited_single",
        { email: email, role: role_label }
      )

      redirect_to invite_options_admin_partner_path(@partner.uuid),
        notice: "📨 #{role_label} invitation sent to #{email}."
    end

    # ------------------------------------------------------------------
    # DEVlSE INVITABLE — BULK INVITE
    # ------------------------------------------------------------------
    def send_invite_bulk
      file = params[:csv]
      unless file&.content_type&.in?(%w[text/csv application/csv application/vnd.ms-excel])
        return redirect_to invite_bulk_admin_partner_path(@partner.uuid),
          alert: "⚠️ Please upload a valid CSV file."
      end

      require "csv"

      service = SectorInvitationService
      model = service.resolve_user_model_for_sector(@partner.sector)
      role_label = service.invite_role_for_sector(@partner.sector)

      invited_count = 0

      CSV.foreach(file.path, headers: false) do |row|
        email = row.first.to_s.strip
        next if email.blank?

        user = model.find_or_initialize_by(email: email)
        user.partner_id = @partner.id if user.respond_to?(:partner_id=)
        user.save! if user.new_record?

        user.invite! unless user.invitation_token.present?

        invited_count += 1
      end

      PartnerAuditLog.log!(
        @partner,
        current_admin_user,
        "bulk_invite",
        { count: invited_count, role: role_label }
      )

      redirect_to invite_options_admin_partner_path(@partner.uuid),
        notice: "📨 #{invited_count} #{role_label.pluralize} invited successfully."
    end


    # ------------------------------------------------------------------
    # PRIVATE HELPERS
    # ------------------------------------------------------------------
    private

    def set_partner
      @partner = Partner.find_by(uuid: params[:uuid])
      return if @partner.present?

      redirect_to admin_partners_path, alert: "⚠️ Partner not found."
    end

    def partner_params
      params.require(:partner).permit(
        :name,
        :contact_person,
        :email,
        :phone_number,
        :website,
        :sector,
        :unit_name,
        :unit_type,
        :description,
        :logo,
        :webhook_url,
        :rejection_reason,
        :rejection_comment,
        :status,
        allowed_transaction_types: []
      )
    end

    def handle_approval(service)
      if service.approve!
        PartnerAuditLog.log!(@partner, current_admin_user, "approved")
        redirect_to admin_partner_path(@partner.uuid),
          notice: "✅ Partner approved."
      else
        redirect_to admin_partner_path(@partner.uuid),
          alert: "⚠️ Approval failed."
      end
    end

    def handle_rejection(service)
      reason  = params.dig(:partner, :rejection_reason)
      comment = params.dig(:partner, :rejection_comment)

      if service.reject!(reason: reason, comment: comment)
        PartnerAuditLog.log!(
          @partner, current_admin_user, "rejected",
          { reason: reason, comment: comment }
        )
        redirect_to admin_partner_path(@partner.uuid), notice: " Partner rejected."
      else
        redirect_to admin_partner_path(@partner.uuid),
          alert: "⚠️ Rejection failed."
      end
    end
  end
end
