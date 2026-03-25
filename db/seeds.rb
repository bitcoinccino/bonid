require "csv"
require "securerandom"
require "digest"
require "bcrypt"

puts "🚨 Cleaning up old data..."
# Delete geographic data first
Address.destroy_all
CommunalSection.destroy_all
Commune.destroy_all
Arrondissement.destroy_all
Department.destroy_all
Bank.destroy_all
# Note: Skipping Partner/Oauth/Branch destroy here—using find_or_create below to preserve verified/demo data

# -------------------------------------------------------------------
# 🗺️ Haiti Administrative Divisions
# -------------------------------------------------------------------

puts "📦 Seeding Departments..."
CSV.foreach(Rails.root.join("db/data/departments.csv"), headers: true) do |row|
  Department.find_or_create_by!(id: row["id"].to_i) do |dept|
    dept.name = row["department_name"]
    dept.postal_code_prefix = row["postal_code_prefix"]
  end
end
puts "✅ Departments seeded: #{Department.count} records"

puts "📦 Seeding Arrondissements..."
CSV.foreach(Rails.root.join("db/data/arrondissements.csv"), headers: true) do |row|
  Arrondissement.find_or_create_by!(id: row["id"].to_i) do |arr|
    arr.name = row["arrondissement_name"]
    arr.department_id = row["department_id"].to_i
    arr.code = row["postal_code_prefix"]
  end
end
puts "✅ Arrondissements seeded: #{Arrondissement.count} records"

department_id_lookup = Arrondissement.all.index_by(&:id).transform_values(&:department_id)

puts "📦 Seeding Communes..."
CSV.foreach(Rails.root.join("db/data/communes.csv"), headers: true) do |row|
  arrondissement_id = row["arrondissement_id"].to_i
  Commune.find_or_create_by!(id: row["id"].to_i) do |commune|
    commune.code = row["commune_id"]
    commune.name = row["commune_name"]
    commune.arrondissement_id = arrondissement_id
    commune.postal_code = row["postal_code_prefix"]
    commune.department_id = department_id_lookup[arrondissement_id]
  end
end
puts "✅ Communes seeded: #{Commune.count} records"

puts "📦 Seeding Communal Sections..."
commune_code_to_id = Commune.all.index_by(&:code).transform_values(&:id)

CSV.foreach(Rails.root.join("db/data/communal_sections.csv"), headers: true) do |row|
  next if row["postal_code"].blank? || row["commune_id"].blank?

  commune_id = commune_code_to_id[row["commune_id"]]
  next unless commune_id

  CommunalSection.find_or_create_by!(id: row["id"].to_i) do |section|
    section.name = row["section_name"]
    section.commune_id = commune_id
    section.postal_code = row["postal_code"]
  end
end
puts "✅ Communal Sections seeded: #{CommunalSection.count} records"
puts "🌍 Geographic seeding complete!"

# -------------------------------------------------------------------
# 🏦 Haitian and Foreign-Linked Banks
# -------------------------------------------------------------------

puts "🏦 Seeding Banks..."
banks = [
  { name: "Banque Nationale de Crédit (BNC)", swift_code: "BNCHHTPP", country: "Haiti" },
  { name: "Banque de la République d'Haïti (BRH)", swift_code: "BRHAHTPP", country: "Haiti" },
  { name: "Banque de l'Union Haïtienne (BUH)", swift_code: "BUHEHTPP", country: "Haiti" },
  { name: "Banque Populaire Haïtienne (BPH)", swift_code: "BPHAHTPP", country: "Haiti" },
  { name: "Unibank S.A.", swift_code: "UBNKHTPP", country: "Haiti" },
  { name: "Sogebank S.A.", swift_code: "SOGHHTPP", country: "Haiti" },
  { name: "Sogebel", swift_code: "SOGLHTPP", country: "Haiti" },
  { name: "Capital Bank S.A.", swift_code: "CAPBHTPP", country: "Haiti" },
  { name: "Citibank N.A. (Haiti)", swift_code: "CITIHTPI", country: "Haiti" },
  { name: "Le Levier – Fédération des Caisses Populaires Haïtiennes", swift_code: "LEVIHTPP", country: "Haiti" },
  { name: "Unibank New York Representative Office", swift_code: "UBNKUS33", country: "United States", verified_partner: true },
  { name: "Banque Nationale de Crédit (BNC) Miami Rep Office", swift_code: "BNCHUS3M", country: "United States", verified_partner: true },
  { name: "Sogebank New York Representative Office", swift_code: "SOGHUS33", country: "United States", verified_partner: true },
  { name: "Citibank N.A. – New York", swift_code: "CITIUS33", country: "United States", verified_partner: true },
  { name: "BRH Foreign Exchange Desk (USD/EUR)", swift_code: "BRHAHTPPFX", country: "Haiti", verified_partner: true },
  { name: "Unibank Paris Partner Correspondent", swift_code: "UBNKFRPP", country: "France", verified_partner: true },
  { name: "BNC Paris Correspondent Branch", swift_code: "BNCHFRPP", country: "France", verified_partner: true }
]

banks.each do |data|
  Bank.find_or_create_by!(swift_code: data[:swift_code]) do |bank|
    bank.name = data[:name]
    bank.country = data[:country]
    bank.verified_partner = data[:verified_partner] || false
  end
end

puts "✅ #{Bank.count} banks seeded successfully."

# -------------------------------------------------------------------
# Demo Partner Applications
# -------------------------------------------------------------------
demo_apps = [
  {
    organization_name: "Demo Bank",
    email: "demo@bonid.ht",
    phone_number: "+50932109876",
    contact_person: "John Doe",
    status: :approved,
    department_sector: "fintech",
    use_cases: %w[kyc onboarding],
    credit_balance: 5_000
  },
  {
    organization_name: "Demo Hospital",
    email: "health@bonid.ht",
    phone_number: "+50956784321",
    contact_person: "Jane Doe",
    status: :pending,
    department_sector: "healthcare",
    use_cases: %w[patient_id insurance_verify],
    credit_balance: 1_000
  }
]

demo_apps.each do |attrs|
  Partner.find_or_create_by!(email: attrs[:email]) do |partner|
    partner.name = attrs[:organization_name]
    partner.phone_number = attrs[:phone_number]
    partner.contact_person = attrs[:contact_person]
    partner.status = attrs[:status]
    partner.sector = attrs[:department_sector]
    partner.use_cases = attrs[:use_cases]
    partner.credit_balance = attrs[:credit_balance]
  end
end

puts "✅ Demo Partners seeded: #{Partner.count} records"

# -------------------------------------------------------------------
# Demo Partners, Branches, and OAuth Applications
# -------------------------------------------------------------------
puts "🌱 Seeding demo partners, branches, and OAuth applications..."

# Seed demo partners (no destroy_all to preserve verified ones later)
demo_partners = [
  { name: "Demo Partner A", slug: "demo-a", sector: "banking" },
  { name: "Demo Partner B", slug: "demo-b", sector: "healthcare" }
]

demo_partners.each do |attrs|
  Partner.find_or_create_by!(slug: attrs[:slug]) do |partner|
    partner.name = attrs[:name]
    partner.sector = attrs[:sector]
    partner.credit_balance = 1_000
  end
end

# Seed branches (idempotent)
Partner.all.each do |partner|
  PartnerBranch.find_or_create_by!(partner_id: partner.id, name: "#{partner.name} Main Branch")
end

# Seed OAuth Applications (idempotent)
Partner.all.each do |partner|
  uid = SecureRandom.hex(10)
  secret = SecureRandom.hex(20)
  secret_digest = BCrypt::Password.create(secret)

  OauthApplication.find_or_create_by!(partner_id: partner.id, uid: uid) do |app|
    app.name = "#{partner.name} OAuth App"
    app.secret_digest = secret_digest
    app.redirect_uri = "https://example.com/oauth/callback"
  end
end

puts "✅ Demo partners, branches, and OAuth Apps seeded successfully!"

# -------------------------------------------------------------------
# 👥 Demo Users (NEW: Required for Identity/Consent)
# -------------------------------------------------------------------
puts "👥 Seeding demo users..."
demo_users = [
  {
    email: "user1@example.com",
    password: "password",
    first_name: "John",
    last_name: "Doe"
    # Add more fields like confirmed_at: Time.current if using Devise
  },
  {
    email: "user2@example.com",
    password: "password",
    first_name: "Jane",
    last_name: "Smith"
    # Add more fields as needed
  }
]

demo_users.each do |attrs|
  User.find_or_create_by!(email: attrs[:email]) do |user|
    user.password = attrs[:password]
    user.first_name = attrs[:first_name]
    user.last_name = attrs[:last_name]
    # user.confirmed_at = Time.current if needed
  end
end

puts "✅ Demo users seeded: #{User.count} records"

# -------------------------------------------------------------------
# Demo Identity Submissions and Consent Grants
# -------------------------------------------------------------------
puts "🌱 Seeding demo Identity Submissions and Consent Grants..."
users = User.limit(2)
partners = Partner.limit(2)  # Now includes demo partners

users.each do |user|
  IdentitySubmission.find_or_create_by!(user_id: user.id, id_type: "cin") do |submission|
    submission.partner = partners.sample  # FIXED: Set partner to satisfy not-null constraint
    submission.status = "pending"
    # Add fields like submitted_at: Time.current if required
  end
  ConsentGrant.find_or_create_by!(partner: partners.sample, citizen: user) do |grant|  # FIXED: Use :partner and :citizen associations
    grant.status = :approved  # Use enum symbol
    grant.requested_scopes = [ "read:identity", "write:consent" ]  # FIXED: Set to satisfy validation
    # Add fields like granted_at: Time.current if required
  end
end

puts "✅ Demo Identity Submissions and Consent Grants seeded."

# -------------------------------------------------------------------
# 🤝 Verified Partners (MOVED: After demo to layer on top)
# -------------------------------------------------------------------
puts "🌱 Seeding verified API partners..."
default_partners = [
  { name: "US Embassy", slug: "us-embassy", sector: "embassy_services", env_key: "US_EMBASSY_API_KEY" },
  { name: "SogeBank", slug: "sogebank", sector: "banking", env_key: "PARTNER_BANK_API_KEY" },
  { name: "Ministry of Interior", slug: "ministry-of-interior", sector: "government", env_key: "MINISTRY_OF_INTERIOR_API_KEY" }
]

default_partners.each do |attrs|
  key = ENV[attrs[:env_key]]
  if key.blank?
    # Dev fallback: Use dummy key (comment out for prod!)
    key = SecureRandom.hex(32)
    puts "⚠️ Using dummy key for #{attrs[:name]} (ENV missing)"
  end

  digest = Digest::SHA256.hexdigest(key)

  Partner.find_or_create_by!(slug: attrs[:slug]) do |partner|
    partner.name = attrs[:name]
    partner.sector = attrs[:sector]
    partner.verified_at = Time.current
    partner.active = true
    partner.api_key_digest = digest
    partner.credit_balance = 10_000
  end
end

puts "✅ Verified partners seeded (with fallbacks if ENV missing)."

# -------------------------------------------------------------------
# 🏠 Addresses (OPTIONAL: Add if needed)
# -------------------------------------------------------------------
# puts "🏠 Seeding demo addresses..."
# Example:
# Address.create!(street: "123 Rue Example", communal_section: CommunalSection.first, partner: Partner.first)
# puts "✅ Addresses seeded."

# -------------------------------------------------------------------
# 💳 Transaction Consents (all types for demo/testing)
# -------------------------------------------------------------------
puts "💳 Seeding Transaction Consents..."

tc_citizen = User.first
tc_partner = Partner.where(sector: "banking").first || Partner.first

if tc_citizen && tc_partner
  transaction_samples = [
    # ── Financial ──
    { transaction_type: "account_opening",  amount: 0,      currency: "HTG", description: "New savings account",       status: :approved },
    { transaction_type: "wire_transfer",    amount: 25_000, currency: "HTG", description: "Wire to BNC account",       status: :approved },
    { transaction_type: "p2p_transfer",     amount: 5_000,  currency: "HTG", description: "Send to Jean-Pierre",       status: :pending  },
    { transaction_type: "remittance",       amount: 150,    currency: "USD", description: "Diaspora remittance",       status: :approved },
    { transaction_type: "bill_payment",     amount: 3_500,  currency: "HTG", description: "EDH electricity bill",      status: :denied   },
    { transaction_type: "merchant_payment", amount: 1_200,  currency: "HTG", description: "Caribbean Supermarket",     status: :approved },
    { transaction_type: "cash_out",         amount: 10_000, currency: "HTG", description: "ATM withdrawal",            status: :approved },
    { transaction_type: "cash_in",          amount: 8_000,  currency: "HTG", description: "Branch deposit",            status: :pending  },
    { transaction_type: "mobile_topup",     amount: 500,    currency: "HTG", description: "Digicel top-up",            status: :approved },
    { transaction_type: "loan_application", amount: 50_000, currency: "HTG", description: "Small business loan",       status: :pending  },
    # ── Identity & Compliance ──
    { transaction_type: "kyc_check",        amount: nil,    currency: "HTG", description: "KYC identity verification", status: :approved },
    { transaction_type: "balance_inquiry",  amount: nil,    currency: "HTG", description: "Account balance check",     status: :approved },
    { transaction_type: "age_verification", amount: nil,    currency: "HTG", description: "Age check for service",     status: :denied   },
    # ── Documents & Services ──
    { transaction_type: "card_issuance",      amount: 1_500, currency: "HTG", description: "New debit card",            status: :approved },
    { transaction_type: "insurance_claim",    amount: 75_000, currency: "HTG", description: "Health insurance claim",   status: :pending  },
    { transaction_type: "document_signing",   amount: nil,    currency: "HTG", description: "Notarized contract",       status: :approved },
    { transaction_type: "government_service", amount: 2_000,  currency: "HTG", description: "Passport renewal fee",     status: :approved }
  ]

  otp_code = "123456"
  otp_digest = BCrypt::Password.create(otp_code)

  transaction_samples.each do |sample|
    existing = TransactionConsent.find_by(
      citizen_id: tc_citizen.id,
      partner_id: tc_partner.id,
      transaction_type: sample[:transaction_type]
    )
    next if existing

    consent = TransactionConsent.new(
      citizen: tc_citizen,
      partner: tc_partner,
      transaction_type: sample[:transaction_type],
      amount: sample[:amount],
      currency: sample[:currency],
      description: sample[:description],
      status: sample[:status],
      scopes: ["read:identity"],
      otp_digest: otp_digest,
      otp_expires_at: 30.minutes.from_now,
      reference_id: "SEED-#{sample[:transaction_type].upcase}-#{SecureRandom.hex(4)}"
    )

    consent.save!

    # Set decided_at for non-pending consents
    unless sample[:status] == :pending
      consent.update_columns(decided_at: consent.created_at + 2.minutes)
    end
  end

  puts "✅ Transaction Consents seeded: #{TransactionConsent.count} records (all 17 types)"
  puts "   💡 OTP for pending consents: #{otp_code}"
else
  puts "⚠️ Skipping Transaction Consents (no user or banking partner found)"
end

puts "🎉 All seeds completed successfully!"
