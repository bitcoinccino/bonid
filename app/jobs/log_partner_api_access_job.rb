# frozen_string_literal: true

class LogPartnerApiAccessJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  discard_on ActiveRecord::RecordInvalid

  def perform(partner_id:, endpoint:, request_method:, status_code:, response_time_ms:, ip_address:, user_agent:, requested_at:)
    PartnerApiLog.create!(
      partner_id: partner_id,
      endpoint: endpoint,
      request_method: request_method,
      status_code: status_code,
      status: status_category(status_code),
      response_time_ms: response_time_ms,
      ip_address: ip_address,
      user_agent: user_agent,
      requested_at: Time.parse(requested_at)
    )
  end

  private

  def status_category(code)
    case code.to_i
    when 200..299 then :success
    when 400..499 then :client_error
    else :server_error
    end
  end
end
