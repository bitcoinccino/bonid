# frozen_string_literal: true

# Handles secure, atomic approval of IdentitySubmissions
# Ensures readiness, logging, and safe QR regeneration.
class IdentitySubmissionApproverService
  include ActiveModel::Validations

  attr_reader :submission, :actor, :context

  def initialize(submission, actor, context: :manual)
    @submission = submission
    @actor = actor
    @context = context
  end

  # === Public Entry Point ===
  def self.call(submission, actor, context: :manual)
    new(submission, actor, context:).call
  end

  def call
    raise ArgumentError, "Missing submission" unless submission
    raise ArgumentError, "Missing actor" unless actor

    # 1️⃣ Validate readiness and permissions
    policy = IdentitySubmissionPolicy.new(actor, submission)
    unless policy.approve?
      return failure("Access denied — #{actor.class.name} not permitted to approve")
    end

    unless policy.ready_for_approval?
      missing = submission.missing_documents
      return failure("Submission incomplete — missing: #{missing.join(', ')}")
    end

    # 2️⃣ Perform atomic approval
    ActiveRecord::Base.transaction do
      submission.update!(
        status: :approved,
        verified_at: Time.current,
        expires_at: 1.year.from_now
      )

      ensure_user_bonid!
      submission.regenerate_combined_qr!

      log_signature!
      notify_success!
    end

    success("Submission ##{submission.id} approved successfully")
  rescue ActiveRecord::RecordInvalid => e
    failure("Record invalid: #{e.record.errors.full_messages.join(', ')}")
  rescue => e
    Rails.logger.error "❌ [ApproverService] #{e.class}: #{e.message}\n#{e.backtrace.take(5).join("\n")}"
    failure("Internal approval error: #{e.message}")
  end

  private

  # === Helper Methods ===

  def ensure_user_bonid!
    user = submission.user
    return unless user

    user.with_lock do
      user.update!(bonid: user.generate_bonid!) if user.bonid.blank?
      submission.update!(bonid: user.bonid) if submission.bonid.blank?
    end
  end

  def log_signature!
    submission.signature_logs.create!(
      reviewer: actor,
      event: "approved",
      context: context,
      occurred_at: Time.current
    )
  rescue => e
    Rails.logger.warn "⚠️ [ApproverService] Signature log failed: #{e.message}"
  end

  def notify_success!
    BonidMailer.with(submission:, actor:).approval_notification.deliver_later
  rescue => e
    Rails.logger.warn "⚠️ [ApproverService] Mail delivery failed: #{e.message}"
  end

  def success(message)
    { success: true, message:, submission: }
  end

  def failure(message)
    { success: false, message:, submission: }
  end
end
