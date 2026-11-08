# frozen_string_literal: true

# ActiveJob logs job arguments on enqueue/perform by default, and
# filter_parameters does NOT apply to them. Mailers are called with raw
# OTPs and tokens (e.g. CitizenOtpService -> mailer.with(otp: raw_otp)),
# so every deliver_later would write live login codes to the log.
# Turn argument logging off for all mail deliveries.
Rails.application.config.after_initialize do
  ActionMailer::MailDeliveryJob.log_arguments = false
end
