# app/mailers/partner_portal/hospital_mailer.rb
# frozen_string_literal: true

module PartnerPortal
  class HospitalMailer < VerifyemMailer
    default from: "noreply@verifyem.ht"

    def record_verified(user:, hospital:)
      @user = user
      @hospital = hospital
      mail(
        to: @user.email,
        subject: "BonID: Health record verified by #{@hospital.name}"
      )
    end

    def record_rejected(user:, hospital:, reason:)
      @user = user
      @hospital = hospital
      @reason = reason
      mail(
        to: @user.email,
        subject: "BonID: Record verification rejected by #{@hospital.name}"
      )
    end
  end
end
