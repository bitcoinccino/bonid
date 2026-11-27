# frozen_string_literal: true

class Citizens::NameChangeMailer < ApplicationMailer
  layout "mailer" # shared Haitian-blue email style (layouts/mailer)

  def reverification_required
    @user = params[:user]
    @ncr  = params[:name_change_request]

    # In the citizen's language (see Citizens::BaseMailer#with_citizen_locale)
    I18n.with_locale(@user.portal_locale) do
      mail(to: @user.email, subject: t("mailers.name_change.subject"))
    end
  end
end
