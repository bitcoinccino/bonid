# app/services/moncash_adapter.rb
class MoncashAdapter
  def self.sync(user, payload)
    profile = user.bank_profiles.find_or_initialize_by(wallet_provider: "MonCash")

    # ✅ Required fields
    profile.bank_name = "MonCash"
    profile.account_number = payload["wallet_number"]
    profile.wallet_address = payload["wallet_number"]

    # ✅ Optional / contextual fields
    profile.currency = "HTG"
    profile.verification_source = "MonCash API"
    profile.kyc_verified = payload["kyc_status"] == "verified"
    profile.last_synced_at = Time.current
    profile.metadata = payload

    profile.save!
  end
end
