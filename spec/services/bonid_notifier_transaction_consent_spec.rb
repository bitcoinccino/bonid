# frozen_string_literal: true

require "rails_helper"

RSpec.describe BonidNotifier, ".notify_transaction_consent signing" do
  let(:secret)  { SecureRandom.hex(32) }
  let(:partner) { build_stubbed(:partner, webhook_secret: secret) }
  let(:consent) do
    double(
      "TransactionConsent",
      id: 1,
      partner: partner,
      partner_id: partner.id,
      callback_url: "https://partner.example.com/bonid/webhook",
      consent_token: "81f81ef7b9f5339085b7",
      citizen: double(bonid: "BZ-1970-M-ND-P2334-0B6"),
      transaction_type: "wire_transfer",
      status: "denied",
      reference_id: "ref-1",
      amount: BigDecimal("5000"),
      currency: "HTG",
      signature: nil,
      decided_at: Time.current,
      expires_at: 10.minutes.from_now,
      biometric_verified_at: nil
    )
  end

  let(:ok) { Net::HTTPOK.new("1.1", "200", "OK") }

  it "signs the exact body sent with the partner's webhook secret" do
    sent = {}
    allow(described_class).to receive(:send_request) do |_uri, body, headers|
      sent[:body] = body
      sent[:headers] = headers
      ok
    end

    described_class.notify_transaction_consent(consent)

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, sent[:body])
    expect(sent[:headers]["X-BonID-Signature"]).to eq(expected)
    expect(sent[:headers]["X-BonID-Timestamp"]).to match(/\A\d+\z/)
    expect(sent[:headers]["X-BonID-Event"]).to eq("transaction_consent.denied")
  end

  it "does not send (and logs + audits) when the partner has no webhook secret" do
    partner.webhook_secret = nil
    allow(described_class).to receive(:send_request)
    allow(Rails.logger).to receive(:error)
    allow(PartnerAuditLog).to receive(:create!)

    described_class.notify_transaction_consent(consent)

    expect(described_class).not_to have_received(:send_request)
    expect(Rails.logger).to have_received(:error).with(/no webhook secret/)
    expect(PartnerAuditLog).to have_received(:create!)
      .with(hash_including(event: "transaction_callback_unsigned_blocked"))
  end
end
