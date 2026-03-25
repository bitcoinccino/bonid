require "rails_helper"

RSpec.describe Partner, type: :model do
  describe "API key lifecycle" do
    let(:partner) { Partner.create!(name: "US Embassy", slug: "us-embassy", active: true) }

    it "generates a valid API key digest on creation" do
      expect(partner.api_key_digest).to be_present
      expect(partner.generated_api_key).to be_present
      expect(partner.api_key_digest).to eq(Digest::SHA256.hexdigest(partner.generated_api_key))
    end

    it "finds partner by valid API key" do
      key = partner.generated_api_key
      found = Partner.find_by_api_key(key)
      expect(found).to eq(partner)
    end

    it "does not find partner with invalid key" do
      expect(Partner.find_by_api_key("fake_key")).to be_nil
    end

    it "rotates API key and changes digest" do
      old_digest = partner.api_key_digest
      new_key = partner.rotate_api_key!
      partner.reload
      expect(partner.api_key_digest).not_to eq(old_digest)
      expect(Digest::SHA256.hexdigest(new_key)).to eq(partner.api_key_digest)
    end

    it "verifies payload signature correctly" do
      payload = "test_data"
      sig = partner.sign_payload(payload)
      expect(partner.verify_signature(payload, sig)).to be true
      expect(partner.verify_signature(payload, "wrong_signature")).to be false
    end
  end

  describe ".valid_api_key?" do
    let!(:partner) { Partner.create!(name: "BonID Bank", slug: "bonid-bank", active: true) }

    it "returns true for valid key" do
      expect(Partner.valid_api_key?(partner.generated_api_key)).to be true
    end

    it "returns false for invalid key" do
      expect(Partner.valid_api_key?("invalid")).to be false
    end
  end
end
