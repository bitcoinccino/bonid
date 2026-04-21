# frozen_string_literal: true

# Ajan::AjanMailer
# ================
# Agent Portal transactional email. Separate from Citizens::CitizenMailer so
# the OTP code email addresses the recipient as an Ajan (agent), not as a
# BonID citizen — the UX context is their partner role, not their citizen
# identity.
module Ajan
  class AjanMailer < VerifyemMailer
    default from: "ajan@verifyem.ht"
    layout "verifyem_mailer"

    def otp_login
      @user = params[:user]
      @otp  = params[:otp]
      @email_product = "bonid"

      mail(
        to: @user.email,
        subject: "Pòtay Ajan: Kòd Koneksyon Ou"
      )
    end
  end
end
