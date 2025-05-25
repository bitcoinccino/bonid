class Admin::IdentitySubmissionsController < Admin::ApplicationController
  before_action :set_submission, only: [:show, :update, :approve_bin, :reject_bin, :approve_reset, :reject_reset]

  def index
    @submissions = IdentitySubmission.includes(:user).order(created_at: :desc)
    @submissions = @submissions.where(status: params[:status]) if params[:status].present?
    @submissions = @submissions.where(submission_type: params[:submission_type]) if params[:submission_type].present?
    @submissions = @submissions.page(params[:page]).per(20)

    @bonbin_count = IdentitySubmission.where(staged_for: :bonbin).count
    @badbin_count = IdentitySubmission.where(staged_for: :badbin).count
  end

  def show; end

  def update
    if params[:approve] == "true"
      @submission.mark_as_verified!
      redirect_to admin_identity_submission_path(@submission), notice: "Submission approved."
    elsif params[:reject] == "true"
      if params[:identity_submission].nil? || params[:identity_submission][:rejection_reason].blank?
        return redirect_to admin_identity_submission_path(@submission), alert: "Please select a rejection reason."
      end

      @submission.update(
        status: :rejected,
        rejection_reason: params[:identity_submission][:rejection_reason],
        other_reason: params[:identity_submission][:other_reason]
      )

      redirect_to admin_identity_submission_path(@submission), notice: "Submission rejected."
    else
      redirect_to admin_identity_submission_path(@submission), alert: "Unknown update action."
    end
  end

  def approve_bin
    if @submission.approved? || @submission.rejected?
      redirect_to admin_identity_submission_path(@submission), alert: "This submission is already finalized."
    else
      @submission.update!(staged_for: :bonbin)
      redirect_to admin_identity_submission_path(@submission), notice: "Submission added to BonBin for future approval."
    end
  end

  def reject_bin
    if @submission.approved? || @submission.rejected?
      redirect_to admin_identity_submission_path(@submission), alert: "This submission is already finalized."
    elsif params[:identity_submission].nil? || params[:identity_submission][:rejection_reason].blank?
      redirect_to admin_identity_submission_path(@submission), alert: "Please select a rejection reason."
    else
      @submission.update!(
        staged_for: :badbin,
        rejection_reason: params[:identity_submission][:rejection_reason],
        other_reason: params[:identity_submission][:other_reason]
      )
      redirect_to admin_identity_submission_path(@submission), notice: "Submission added to BadBin for future rejection."
    end
  end

  def bulk_update
    if params[:submission_ids].blank?
      redirect_to admin_identity_submissions_path, alert: "Please select at least one submission." and return
    end

    ids = params[:submission_ids].map(&:to_i)
    action = params[:bulk_action]

    case action
    when "approve_bin"
      IdentitySubmission.where(id: ids, staged_for: :bonbin).update_all(status: :approved)
      redirect_to admin_identity_submissions_path, notice: "All BonBin submissions have been approved."
    when "reject_bin"
      IdentitySubmission.where(id: ids, staged_for: :badbin).find_each do |submission|
        submission.update!(status: :rejected)
      end
      redirect_to admin_identity_submissions_path, notice: "All BadBin submissions have been rejected."
    else
      redirect_to admin_identity_submissions_path, alert: "Invalid bulk action selected."
    end
  end

  def approve_reset
    if @submission.reset_requested_at.present?
      @submission.update!(
        verification_token: SecureRandom.hex(40),
        verified_at: Time.current,
        expires_at: 1.year.from_now,
        reset_requested_at: nil,
        reset_request_status: :approved,
        status: :approved,
        reissued_at: Time.current
      )
      redirect_to admin_identity_submission_path(@submission), notice: "Reset approved and BonID reissued."
    else
      redirect_to admin_identity_submission_path(@submission), alert: "No reset request to approve."
    end
  end

  def reject_reset
    if params[:identity_submission].nil? || params[:identity_submission][:reset_rejection_reason].blank?
      return redirect_to admin_identity_submission_path(@submission), alert: "Please select a rejection reason."
    end

    if @submission.reset_requested_at.present?
      @submission.update!(
        reset_rejection_reason: params[:identity_submission][:reset_rejection_reason],
        reset_other_reason: params[:identity_submission][:reset_other_reason],
        reset_request_status: :rejected
      )
      redirect_to admin_identity_submission_path(@submission), notice: "Reset request rejected."
    else
      redirect_to admin_identity_submission_path(@submission), alert: "No reset request to reject."
    end
  end

  private

  def set_submission
    @submission = IdentitySubmission.find(params[:id])
  end
end
