# frozen_string_literal: true

class RecordConsentAccessJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(citizen_id:, partner_id:)
    grant = ConsentGrant.active.find_by(citizen_id: citizen_id, partner_id: partner_id)
    grant&.record_access!
  end
end
