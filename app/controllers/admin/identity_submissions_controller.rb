# app/controllers/admin/identity_submissions_controller.rb
# frozen_string_literal: true

class Admin::IdentitySubmissionsController < Admin::ApplicationController
  # ---------------------------------------------------------------------------
  # FILTERS
  # ---------------------------------------------------------------------------
  before_action :set_submission, only: %i[
    show update approve approve_bin reject_bin
    approve_reset reject_reset regenerate_qr verify_signature retry_face_match
  ]
  before_action :authorize_submission, only: %i[
    show update approve approve_bin reject_bin
    approve_reset reject_reset regenerate_qr verify_signature retry_face_match
  ]

  # ---------------------------------------------------------------------------
  # INDEX
  # ---------------------------------------------------------------------------
  def index
    @submissions = IdentitySubmission.includes(:user).order(created_at: :desc)
    @submissions = @submissions.where(status: params[:status]) if params[:status].present?
    @submissions = @submissions.where(submission_type: params[:submission_type]) if params[:submission_type].present?
    @submissions = @submissions.page(params[:page]).per(20)

    @status_counts = Rails.cache.fetch("admin/submissions/status_counts", expires_in: 2.minutes) do
      IdentitySubmission.group(:status).count.transform_keys(&:to_sym)
    end
    @bonbin_count = Rails.cache.fetch("admin/submissions/bonbin_count", expires_in: 2.minutes) do
      IdentitySubmission.where(staged_for: :bonbin).count
    end
    @badbin_count = Rails.cache.fetch("admin/submissions/badbin_count", expires_in: 2.minutes) do
      IdentitySubmission.where(staged_for: :badbin).count
    end
  end

  # ---------------------------------------------------------------------------
  # SHOW
  # ---------------------------------------------------------------------------
  def show
    unless @submission
      Rails.logger.warn "⚠️ Admin tried to access IdentitySubmission uuid=#{params[:uuid]} — record not found."
      redirect_to admin_identity_submissions_path, alert: "Submission not found."
      return
    end

    @qr_scan_logs = @submission.qr_scan_logs.includes(:partner, :officer)
  end

  # ---------------------------------------------------------------------------
  # UPDATE (manual approve/reject)
  # ---------------------------------------------------------------------------
  def update
    if params[:approve] == "true"
      authorize @submission, :approve?
      if approve_submission!(@submission)
        UserMailer.bonid_approved(@submission.user, @submission).deliver_later
        redirect_to admin_identity_submission_path(@submission.uuid), notice: "Submission approved."
      else
        redirect_to admin_identity_submission_path(@submission.uuid), alert: "Approval failed. Ensure all required files including signature are present."
      end

    elsif params[:reject] == "true"
      authorize @submission, :reject?

      unless rejection_params[:rejection_reason].present? || rejection_params[:other_reason].present?
        return redirect_to admin_identity_submission_path(@submission.uuid), alert: "Please select or provide a rejection reason."
      end

      if @submission.update(
        status: :rejected,
        rejection_reason: rejection_params[:rejection_reason],
        other_reason:     rejection_params[:other_reason]
      )
        UserMailer.bonid_rejected(@submission.user, @submission).deliver_later
        redirect_to admin_identity_submission_path(@submission.uuid), notice: "Submission rejected."
      else
        redirect_to admin_identity_submission_path(@submission.uuid), alert: "Rejection failed."
      end

    else
      redirect_to admin_identity_submission_path(@submission.uuid), alert: "Unknown update action."
    end
  end

  # ---------------------------------------------------------------------------
  # APPROVAL / BIN ACTIONS
  # ---------------------------------------------------------------------------
  def approve
    authorize @submission, :approve?

    unless @submission.signature.attached?
      redirect_to admin_identity_submission_path(@submission.uuid),
                  alert: "Cannot approve submission without a signature."
      return
    end

    approver = current_admin_user || (current_user if current_user&.reviewer?)

    @submission.update!(
      status:              :approved,
      verified_at:          Time.current,
      expires_at:           1.year.from_now,
      verification_token:   SecureRandom.hex(20),
      qr_png_base64:        nil,
      reviewer:             (approver if approver.is_a?(User)),
      reviewed_by_admin:    (approver if approver.is_a?(AdminUser))
    )

    @submission.regenerate_combined_qr! if @submission.respond_to?(:regenerate_combined_qr!)

    begin
      UserMailer.bonid_approved(@submission.user, @submission).deliver_later
    rescue => e
      Rails.logger.error "[MAILER ERROR] Failed to send approval email: #{e.message}"
    end

    respond_to do |format|
      format.html do
        redirect_to admin_identity_submission_path(@submission.uuid),
                    notice: "✅ Submission approved and BonID issued by #{approver&.email || 'System'}."
      end
      format.turbo_stream
    end

  rescue => e
    Rails.logger.error "Approval failed: #{e.message}"
    respond_to do |format|
      format.html { redirect_to admin_identity_submission_path(@submission.uuid), alert: "❌ Approval failed: #{e.message}" }
      format.turbo_stream
    end
  end

  def approve_bin
    authorize @submission, :approve?
    if @submission.status_approved? || @submission.status_rejected?
      redirect_to admin_identity_submission_path(@submission.uuid), alert: "This submission is already finalized."
    else
      @submission.update!(staged_for: :bonbin)
      redirect_to admin_identity_submission_path(@submission.uuid), notice: "Submission added to BonBin for future approval."
    end
  end

  def reject_bin
    authorize @submission, :reject?

    if @submission.status_approved? || @submission.status_rejected?
      redirect_to admin_identity_submission_path(@submission.uuid), alert: "This submission is already finalized."
    elsif rejection_params[:rejection_reason].blank?
      respond_to do |format|
        format.html do
          flash.now[:alert] = "Please select a rejection reason."
          render turbo_stream: turbo_stream.replace(
            "modal-body",
            partial: "admin/identity_submissions/modals/bad_bin_modal",
            locals:  { submission: @submission }
          )
        end
      end
    else
      if @submission.update!(
        staged_for:      :badbin,
        rejection_reason: rejection_params[:rejection_reason],
        other_reason:     rejection_params[:other_reason]
      )
        UserMailer.bonid_rejected(@submission.user, @submission).deliver_later
        redirect_to admin_identity_submission_path(@submission.uuid), notice: "Submission added to BadBin for future rejection."
      else
        redirect_to admin_identity_submission_path(@submission.uuid), alert: "Failed to move submission to BadBin."
      end
    end
  end

  # ---------------------------------------------------------------------------
  # QR / RESET
  # ---------------------------------------------------------------------------
  def regenerate_qr
    authorize @submission, :approve?

    if @submission.status_approved?
      @submission.regenerate_combined_qr!
      flash[:notice] = "QR code regenerated successfully for #{@submission.user.full_name}."
    else
      flash[:alert] = "Cannot regenerate QR code unless the submission is approved."
    end
    redirect_to admin_identity_submission_path(@submission.uuid)
  end

  def approve_reset
    authorize @submission, :reset?

    if @submission.reset_requested_at.present?
      @submission.update!(
        verification_token: SecureRandom.hex(40),
        verified_at:         Time.current,
        expires_at:          1.year.from_now,
        reset_requested_at:  nil,
        reset_request_status: :approved,
        status:              :approved,
        reissued_at:         Time.current,
        reviewed_by_admin:   current_admin_user
      )
      UserMailer.bonid_reset_approved(@submission.user, @submission).deliver_later
      redirect_to admin_identity_submission_path(@submission.uuid), notice: "Reset approved and BonID reissued."
    else
      redirect_to admin_identity_submission_path(@submission.uuid), alert: "No reset request to approve."
    end
  end

  def reject_reset
    authorize @submission, :reset?

    if reset_rejection_params[:reset_rejection_reason].blank? &&
       reset_rejection_params[:reset_other_reason].blank?
      return redirect_to admin_identity_submission_path(@submission.uuid), alert: "Please select or provide a rejection reason."
    end

    if @submission.reset_requested_at.present?
      @submission.update!(
        reset_rejection_reason:  reset_rejection_params[:reset_rejection_reason],
        reset_other_reason:      reset_rejection_params[:reset_other_reason],
        reset_request_status:    :rejected,
        reviewed_by_admin:       current_admin_user
      )
      UserMailer.bonid_reset_rejected(@submission.user, @submission).deliver_later
      redirect_to admin_identity_submission_path(@submission.uuid), notice: "Reset request rejected."
    else
      redirect_to admin_identity_submission_path(@submission.uuid), alert: "No reset request to reject."
    end
  end

  # ---------------------------------------------------------------------------
  # BULK / LOOKUP
  # ---------------------------------------------------------------------------
  def bulk_update
    action = params[:bulk_action]
    ids     = Array(params[:submission_ids])

    case action
    when "approve_bin"
      authorize IdentitySubmission, :approve?
      return redirect_to(admin_identity_submissions_path, alert: "Please select at least one BonBin submission.") if ids.empty?

      approved, failed = [], []
      submissions = IdentitySubmission.where(uuid: ids, staged_for: :bonbin)

      submissions.find_each do |submission|
        if approve_submission!(submission)
          approved << submission.id
          UserMailer.bonid_approved(submission.user, submission).deliver_later
        else
          failed << submission.id
        end
      end

      flash[:notice] = "#{approved.size} BonBin submission(s) approved." if approved.any?
      flash[:alert]  = "Failed to approve #{failed.size} submission(s): #{failed.join(', ')}" if failed.any?
      redirect_to admin_identity_submissions_path

    when "reject_bin"
      authorize IdentitySubmission, :reject?
      submissions = ids.present? ?
        IdentitySubmission.where(uuid: ids, staged_for: :badbin) :
        IdentitySubmission.where(staged_for: :badbin, status: :pending)

      return redirect_to(admin_identity_submissions_path, alert: "No BadBin submissions found to reject.") if submissions.none?

      rejected = []
      submissions.find_each do |submission|
        submission.update!(status: :rejected, staged_for: nil, reviewed_by_admin: current_admin_user)
        UserMailer.bonid_rejected(submission.user, submission).deliver_later
        rejected << submission.id
      end

      flash[:notice] = "#{rejected.size} BadBin submission(s) rejected."
      redirect_to admin_identity_submissions_path

    else
      redirect_to admin_identity_submissions_path, alert: "Invalid bulk action selected."
    end
  end

  def fallback_lookup
    bonid      = params[:bonid].to_s.strip.upcase
    user       = User.find_by(bonid: bonid)
    submission = user&.identity_submissions&.approved&.order(verified_at: :desc)&.first

    respond_to do |format|
      if submission
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "scan_result_frame",
            partial: "admin/identity_submissions/scan_result_valid",
            locals:  { submission: submission, user: user }
          )
        end
        format.html { redirect_to admin_identity_submission_path(submission.uuid) }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "scan_result_frame",
            partial: "admin/identity_submissions/scan_result_invalid",
            locals:  { bonid: bonid, error: "No approved BonID found." }
          )
        end
        format.html { redirect_to admin_identity_submissions_path, alert: "No approved BonID found." }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # VERIFY SIGNATURE
  # ---------------------------------------------------------------------------
  def verify_signature
    unless @submission
      Rails.logger.error "⚠️ No submission found for uuid=#{params[:uuid]}"
      respond_to do |format|
        format.html { redirect_to admin_identity_submissions_path, alert: "Submission not found." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.prepend("flash_messages",
            partial: "shared/flash",
            locals:  { alert: "Submission not found." })
        end
      end
      return
    end

    @submission.update!(
      signature_verified_at:       Time.current,
      signature_verification_method: params[:method],
      signature_verification_note:   params[:note],
      signature_verifier_id:         current_admin_user.id
    )

    @submission.signature_logs.create!(
      action:      "verified",
      user_id:     @submission.user_id,
      verifier_id: current_admin_user.id,
      verified:    true,
      verified_at: Time.current,
      note:        "Verified via Admin panel by #{current_admin_user.email}"
    )

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to admin_identity_submission_path(@submission.uuid),
                                 notice: "Signature verified successfully." }
    end
  end

  # ---------------------------------------------------------------------------
  # RETRY FACE MATCH
  # ---------------------------------------------------------------------------
  def retry_face_match
    authorize @submission, :approve?

    unless @submission.selfie.attached? && (@submission.cin_front.attached? || @submission.passport.attached?)
      redirect_to admin_identity_submission_path(@submission.uuid),
                  alert: "Cannot retry face match: missing selfie or ID document."
      return
    end

    # Clear the cached error result
    current_metadata = @submission.metadata || {}
    current_metadata.delete("face_match")
    @submission.update_column(:metadata, current_metadata)

    # Call the service directly (bypasses FaceMatchJob's status_pending? guard)
    result = FaceMatchService.call(@submission)

    if result[:status] == "error"
      redirect_to admin_identity_submission_path(@submission.uuid),
                  alert: "Face match failed: #{result[:error_message]}"
    else
      redirect_to admin_identity_submission_path(@submission.uuid),
                  notice: "Face match completed: #{result[:status]} (#{result[:similarity]}% similarity)."
    end
  end

  # ---------------------------------------------------------------------------
  # PRIVATE HELPERS
  # ---------------------------------------------------------------------------
  private

  def approve_submission!(submission)
    unless submission.signature.attached?
      flash[:alert] = "Cannot approve submission without a signature."
      return false
    end

    approver = current_admin_user || (current_user if current_user&.reviewer?)

    ActiveRecord::Base.transaction do
      # === Update submission core status ===
      submission.update!(
        status:            :approved,
        verified_at:       Time.current,
        expires_at:        1.year.from_now,
        verification_token: SecureRandom.hex(20),
        qr_png_base64:     nil,
        reviewer:          (approver if approver.is_a?(User)),
        reviewed_by_admin: (approver if approver.is_a?(AdminUser))
      )

      # === Unified BonID handling ===
      # Ensure the user has a BonID before syncing it to the submission
      submission.user.generate_bonid! if submission.user.bonid.blank?
      submission.assign_bonid_from_user if submission.respond_to?(:assign_bonid_from_user)

      # === Audit trail (optional, non-blocking) ===
      if defined?(BonidAssignmentLog)
        BonidAssignmentLog.record!(submission, reviewer: approver)
      end

      # === Regenerate QR (idempotent)
      submission.regenerate_combined_qr! if submission.respond_to?(:regenerate_combined_qr!)
    end

    # === Notify citizen asynchronously ===
    begin
      UserMailer.bonid_approved(submission.user, submission).deliver_later
    rescue => e
      Rails.logger.error "[MAILER ERROR] Approval email failed: #{e.message}"
    end

    true
  rescue => e
    Rails.logger.error "❌ Approval failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    false
  end


  def set_submission
    @submission = params[:uuid].present? ? IdentitySubmission.find_by(uuid: params[:uuid]) : nil
  end

  def authorize_submission
    action =
      if params[:approve] || params[:approve_bin] || params[:approve_reset]
        :approve?
      elsif params[:reject] || params[:reject_bin] || params[:reject_reset]
        :reject?
      elsif params[:bulk_action] == "approve_bin"
        :approve_bin?
      elsif params[:bulk_action] == "reject_bin"
        :reject_bin?
      else
        :update?
      end

    authorize(@submission || IdentitySubmission, action)
  end

  def rejection_params
    params.fetch(:identity_submission, {}).permit(:rejection_reason, :other_reason)
  end

  def reset_rejection_params
    params.fetch(:identity_submission, {}).permit(:reset_rejection_reason, :reset_other_reason)
  end
end


# class Admin::IdentitySubmissionsController < Admin::ApplicationController
#   before_action :set_submission, only: [
#     :show, :update, :approve, :approve_bin, :reject_bin,
#     :approve_reset, :reject_reset, :regenerate_qr
#   ]

#   def index
#     @submissions = IdentitySubmission.includes(:user).order(created_at: :desc)
#     @submissions = @submissions.where(status: params[:status]) if params[:status].present?
#     @submissions = @submissions.where(submission_type: params[:submission_type]) if params[:submission_type].present?
#     @submissions = @submissions.page(params[:page]).per(20)

#     @bonbin_count = IdentitySubmission.where(staged_for: :bonbin).count
#     @badbin_count = IdentitySubmission.where(status: :rejected).count
#   end


#   def show; end

#   def update
#     if params[:approve] == "true"
#       if approve_submission!(@submission)
#         UserMailer.bonid_approved(@submission.user, @submission).deliver_later
#         redirect_to admin_identity_submission_path(@submission.uuid), notice: "Submission approved."
#       else
#         redirect_to admin_identity_submission_path(@submission.uuid), alert: "Approval failed. Ensure all required files including signature are present."
#       end
#     elsif params[:reject] == "true"
#       unless rejection_params[:rejection_reason].present?
#         return redirect_to admin_identity_submission_path(@submission.uuid), alert: "Please select a rejection reason."
#       end
#       if @submission.update(
#         status: :rejected,
#         rejection_reason: rejection_params[:rejection_reason],
#         other_reason: rejection_params[:other_reason]
#       )
#         UserMailer.bonid_rejected(@submission.user, @submission).deliver_later
#         redirect_to admin_identity_submission_path(@submission.uuid), notice: "Submission rejected."
#       else
#         redirect_to admin_identity_submission_path(@submission.uuid), alert: "Rejection failed."
#       end
#     else
#       redirect_to admin_identity_submission_path(@submission.uuid), alert: "Unknown update action."
#     end
#   end

#   def approve
#     unless @submission
#       return redirect_to admin_identity_submissions_path, alert: "Submission not found."
#     end

#     if approve_submission!(@submission)
#       begin
#         UserMailer.bonid_approved(@submission.user, @submission).deliver_later
#       rescue => e
#         Rails.logger.error("[MAILER ERROR] Failed to send approval email for submission #{@submission.id}: #{e.message}")
#       end

#       respond_to do |format|
#         format.html { redirect_to admin_identity_submission_path(@submission.uuid), notice: "✅ Submission approved and BonID issued." }
#         format.turbo_stream do
#           flash.now[:notice] = "✅ Submission approved and BonID issued."
#           render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash")
#         end
#       end
#     else
#       respond_to do |format|
#         format.html { redirect_to admin_identity_submission_path(@submission.uuid), alert: "❌ Approval failed. Ensure signature and required documents are attached." }
#         format.turbo_stream do
#           flash.now[:alert] = "❌ Approval failed. Ensure signature and required documents are attached."
#           render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash")
#         end
#       end
#     end
#   end


#   def approve_bin
#     if @submission.status_approved? || @submission.status_rejected?
#       redirect_to admin_identity_submission_path(@submission.uuid), alert: "This submission is already finalized."
#     else
#       @submission.update!(staged_for: :bonbin)
#       redirect_to admin_identity_submission_path(@submission.uuid), notice: "Submission added to BonBin for future approval."
#     end
#   end

#   def reject_bin
#     if @submission.status_approved? || @submission.status_rejected?
#       redirect_to admin_identity_submission_path(@submission.uuid), alert: "This submission is already finalized."
#     elsif rejection_params[:rejection_reason].blank?
#       redirect_to admin_identity_submission_path(@submission.uuid), alert: "Please select a rejection reason."
#     else
#       @submission.update!(
#         staged_for: :badbin,
#         rejection_reason: rejection_params[:rejection_reason],
#         other_reason: rejection_params[:other_reason]
#       )
#       redirect_to admin_identity_submission_path(@submission.uuid), notice: "Submission added to BadBin for future rejection."
#     end
#   end

#   def regenerate_qr
#     if @submission.status_approved?
#       @submission.regenerate_combined_qr!
#       flash[:notice] = "QR code regenerated successfully for #{@submission.user.full_name}."
#     else
#       flash[:alert] = "Cannot regenerate QR code unless the submission is approved."
#     end

#     redirect_to admin_identity_submission_path(@submission.uuid)
#   end

#   def approve_reset
#     if @submission.reset_requested_at.present?
#       @submission.update!(
#         verification_token: SecureRandom.hex(40),
#         verified_at: Time.current,
#         expires_at: 1.year.from_now,
#         reset_requested_at: nil,
#         reset_request_status: :approved,
#         status: :approved,
#         reissued_at: Time.current
#       )
#       UserMailer.bonid_reset_approved(@submission.user, @submission).deliver_later
#       redirect_to admin_identity_submission_path(@submission.uuid), notice: "Reset approved and BonID reissued."
#     else
#       redirect_to admin_identity_submission_path(@submission.uuid), alert: "No reset request to approve."
#     end
#   end

#   def reject_reset
#     if reset_rejection_params[:reset_rejection_reason].blank?
#       return redirect_to admin_identity_submission_path(@submission.uuid), alert: "Please select a rejection reason."
#     end

#     if @submission.reset_requested_at.present?
#       @submission.update!(
#         reset_rejection_reason: reset_rejection_params[:reset_rejection_reason],
#         reset_other_reason: reset_rejection_params[:reset_other_reason],
#         reset_request_status: :rejected
#       )
#       UserMailer.bonid_reset_rejected(@submission.user, @submission).deliver_later
#       redirect_to admin_identity_submission_path(@submission.uuid), notice: "Reset request rejected."
#     else
#       redirect_to admin_identity_submission_path(@submission.uuid), alert: "No reset request to reject."
#     end
#   end

#   def bulk_update
#     action = params[:bulk_action]
#     ids = Array(params[:submission_ids]).map(&:to_i)

#     case action
#     when "approve_bin"
#       if ids.empty?
#         return redirect_to admin_identity_submissions_path, alert: "Please select at least one BonBin submission."
#       end

#       submissions = IdentitySubmission.where(id: ids, staged_for: :bonbin)
#       submissions.find_each do |submission|
#         next unless approve_submission!(submission)
#         UserMailer.bonid_approved(submission.user, submission).deliver_later
#       end
#       redirect_to admin_identity_submissions_path, notice: "All selected BonBin submissions have been approved."

#     when "reject_bin"
#       # 🔹 If no checkboxes selected, fallback to ALL staged_for :badbin
#       submissions =
#         if ids.empty?
#           IdentitySubmission.where(staged_for: :badbin, status: :pending)
#         else
#           IdentitySubmission.where(id: ids, staged_for: :badbin)
#         end

#       if submissions.none?
#         return redirect_to admin_identity_submissions_path, alert: "No BadBin submissions found to reject."
#       end

#       submissions.find_each do |submission|
#         submission.update!(status: :rejected)
#         UserMailer.bonid_rejected(submission.user, submission).deliver_later
#       end
#       redirect_to admin_identity_submissions_path, notice: "All BadBin submissions have been rejected."

#     else
#       redirect_to admin_identity_submissions_path, alert: "Invalid bulk action selected."
#     end
#   end


#   def fallback_lookup
#     bonid = params[:bonid].to_s.strip.upcase

#     user = User.find_by(bonid: bonid)
#     submission = user&.identity_submissions&.approved&.order(verified_at: :desc)&.first

#     if submission
#       render turbo_stream: turbo_stream.replace(
#         "scan_result_frame",
#         partial: "admin/identity_submissions/scan_result_valid",
#         locals: { submission: submission, user: user }
#       )
#     else
#       render turbo_stream: turbo_stream.replace(
#         "scan_result_frame",
#         partial: "admin/identity_submissions/scan_result_invalid",
#         locals: { bonid: bonid, error: "No approved BonID found." }
#       )
#     end
#   end

#   private

#   def approve_submission!(submission)
#     unless submission.signature.attached?
#       flash[:alert] = "Cannot approve submission without a signature."
#       return false
#     end

#     submission.update!(
#       status: :approved,
#       verified_at: Time.current,
#       expires_at: 1.year.from_now,
#       verification_token: SecureRandom.hex(20),
#       qr_png_base64: nil
#     )
#     submission.regenerate_combined_qr! if submission.respond_to?(:regenerate_combined_qr!)
#     true
#   rescue StandardError => e
#     Rails.logger.error "Approval failed: #{e.message}"
#     false
#   end

#   def set_submission
#     @submission = IdentitySubmission.find_by(id: params[:id])
#     redirect_to admin_identity_submissions_path, alert: "Submission not found." unless @submission
#   end

#   def rejection_params
#     params.fetch(:identity_submission, {}).permit(:rejection_reason, :other_reason)
#   end

#   def reset_rejection_params
#     params.fetch(:identity_submission, {}).permit(:reset_rejection_reason, :reset_other_reason)
#   end
# end
