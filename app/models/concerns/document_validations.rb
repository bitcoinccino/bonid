# frozen_string_literal: true

module DocumentValidations
  extend ActiveSupport::Concern

  included do
    validate :required_documents_present, unless: -> { skip_document_validations }
    attr_accessor :skip_document_validations
  end

  def required_documents_present
    validate_primary_id
    validate_selfie
    validate_supporting_documents
  end

  private

  def validate_primary_id
    cin_valid = cin_front.attached? && cin_back.attached?
    passport_valid = passport.attached?

    unless cin_valid || passport_valid
      errors.add(:base, "You must upload both CIN Front and Back OR a Passport.")
    end
  end

  def validate_selfie
    errors.add(:selfie, "must be attached.") unless selfie.attached?
  end

  def validate_supporting_documents
    support_docs = [
      digicel_phone_bill, natcom_phone_bill, baptismal_certificate, birth_certificate,
      adoption_certificate, naturalization_monitor_copy, archives_extract, pnh_record,
      bank_record, western_union_record, moneygram_record, sendwave_record,
      unitransfer_record, taptap_record, additional_proof
    ]

    unless support_docs.any?(&:attached?)
      errors.add(:base, "You must upload at least one supporting document.")
    end
  end
end
