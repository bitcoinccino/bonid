# frozen_string_literal: true

class IdentitySubmissionPolicy < ApplicationPolicy
  attr_reader :user, :submission

  def initialize(user, submission)
    @user = user
    @submission = submission
  end

  # === Standard actions ===
  def index?
    admin_or_reviewer?
  end

  def show?
    admin_or_reviewer? || user_has?(:verifier)
  end

  # === Approval / Rejection ===
  def approve?
    admin_or_reviewer? || user_has?(:approver)
  end

  def reject?
    admin_or_reviewer? || user_has?(:reviewer)
  end

  # === Reset flow ===
  def reset?
    admin_or_reviewer? || user_has?(:resetter)
  end

  def approve_reset?
    admin_or_reviewer?
  end

  def reject_reset?
    admin_or_reviewer?
  end

  # === Bin flows ===
  def approve_bin?
    admin_or_reviewer?
  end

  def reject_bin?
    admin_or_reviewer?
  end

  # === QR regeneration ===
  def regenerate_qr?
    approve? # piggyback on approve logic
  end

  # === Bulk actions ===
  def bulk_update?
    approve? || reject?
  end

  # === Update (covers generic update actions in controllers) ===
  def update?
    approve? || reject?
  end

  # ===============================================================
  # === DOCUMENT COMPLETENESS CHECK (Approval Readiness Layer) ===
  # ===============================================================
  #
  # Grok-style reasoning: this policy decides *if the submission*
  # *is eligible* for approval, not whether the user is allowed to.
  # Keeps IdentitySubmission.rb pure and testable.
  #
  def ready_for_approval?
    case submission.submission_type.to_sym
    when :initial
      base_documents_present? && proof_of_address_present?
    when :resubmission, :reissue
      base_documents_present?
    else
      false
    end
  end

  private

  # --- Common checks ---
  def base_documents_present?
    submission.selfie.attached? &&
      submission.signature.attached? &&
      (submission.cin_front.attached? || submission.passport.attached?)
  end

  def proof_of_address_present?
    submission.proof_of_address.attached? ||
      submission.digicel_phone_bill.attached? ||
      submission.natcom_phone_bill.attached?
  end

  # --- Role helpers ---
  def admin_or_reviewer?
    return false unless user
    return true if user.is_a?(AdminUser) || user.is_a?(Admin)

    user.respond_to?(:has_role?) &&
      (user.has_role?(:admin) || user.has_role?(:reviewer))
  end

  def user_has?(role)
    user&.respond_to?(:has_role?) && user.has_role?(role)
  end
end
