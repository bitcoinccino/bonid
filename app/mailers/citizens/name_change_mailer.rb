# frozen_string_literal: true

class Citizens::NameChangeMailer < ApplicationMailer
  layout "mailer_citizen"

  def reverification_required
    @user = params[:user]
    @ncr  = params[:name_change_request]

    mail(
      to: @user.email,
      subject: "BonID: Chanjman non ou apwouve — Reverifikasyon obligatwa"
    )
  end
end
