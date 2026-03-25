# frozen_string_literal: true

Devise.setup do |config|
  config.secret_key = Rails.application.credentials.dig(:devise, :secret_key) ||
                      Rails.application.secret_key_base

  config.mailer_sender = "no-reply@verifyem.ht"
  config.mailer        = "UserMailer"
  config.parent_mailer = "ApplicationMailer"

  require "devise/orm/active_record"

  config.case_insensitive_keys = [ :email ]
  config.strip_whitespace_keys = [ :email ]
  config.skip_session_storage  = [ :http_auth ]

  config.stretches = Rails.env.test? ? 1 : 12
  config.reconfirmable = true
  config.password_length = 8..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.reset_password_within = 6.hours
  config.expire_all_remember_me_on_sign_out = true
  config.sign_out_via = :delete

  config.responder.error_status   = :unprocessable_entity
  config.responder.redirect_status = :see_other
  config.scoped_views = true
  config.sign_out_all_scopes = false

  config.mailer_sender = lambda do |record|
    if record.respond_to?(:has_role?) && record.has_role?(:partner_admin)
      "no-reply@partner.verifyem.ht"
    elsif record.respond_to?(:has_role?) && record.has_role?(:officer)
      "no-reply@pnh.verifyem.ht"
    else
      "no-reply@bonid.ht"
    end
  end
end

# ⚠️ REMOVED: Rails.application.routes.default_url_options overrides
# They break development.rb NGROK host overrides.
