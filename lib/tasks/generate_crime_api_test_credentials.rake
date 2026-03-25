# frozen_string_literal: true

# lib/tasks/generate_crime_api_test_credentials.rake
#
# Generate test credentials for BonID Partner API
# (Identity Verification + Crime Status)
#
# Usage:
#   bundle exec rails crime_api:generate_test_credentials
#
namespace :crime_api do
  desc "Generate test credentials for BonID Partner API (Identity + Crime Status)"
  task generate_test_credentials: :environment do
    puts "=" * 70
    puts "BONID PARTNER API - TEST CREDENTIALS"
    puts "=" * 70
    puts ""

    # Find or create a test partner
    partner = Partner.find_by(slug: "police-national-d-haiti")
    partner ||= Partner.where.not(verified_at: nil).where(active: true).first

    if partner.nil?
      puts "ERROR: No verified active partner found!"
      puts "Create a partner first or run seeds."
      exit 1
    end

    puts "Partner: #{partner.name} (#{partner.slug})"
    puts "Sector:  #{partner.sector || 'N/A'}"
    puts ""

    # Generate a new API key for testing
    raw_key = "bonid_live_test_#{SecureRandom.hex(16)}"
    digest = Digest::SHA256.hexdigest(raw_key)
    partner.update!(api_key_digest: digest)

    puts "API Key (save this - only shown once):"
    puts "-" * 70
    puts raw_key
    puts "-" * 70
    puts ""

    # Add all API scopes to partner
    new_scopes = %w[
      openid profile email phone address
      identity:verify identity:details
      crime:status crime:reports crime:certificate crime:full
    ]
    partner.update!(allowed_scopes: new_scopes)
    puts "Updated allowed_scopes:"
    puts "  #{partner.reload.allowed_scopes.join(', ')}"
    puts ""

    # Find a test citizen (user) for the token
    citizen = User.where.not(bonid: nil).first
    if citizen.nil?
      puts "WARNING: No user with BonID found. Creating token without citizen..."
    end

    # Create OAuth token with all API scopes
    token = OauthAccessToken.create!(
      partner: partner,
      citizen: citizen,
      token: SecureRandom.hex(32),
      scopes: %w[identity:verify identity:details crime:status crime:reports crime:certificate],
      expires_at: 24.hours.from_now
    )

    puts "OAuth Token (expires in 24h):"
    puts "-" * 70
    puts token.token
    puts "-" * 70
    puts ""
    puts "Token Scopes: #{token.scopes.join(', ')}"
    puts ""

    # Show sample BonIDs/BonTouris to test with
    puts "=" * 70
    puts "SAMPLE IDS TO TEST"
    puts "=" * 70
    puts ""

    # Citizens with verified BonID
    puts "CITIZENS (BonID):"
    User.joins(:identity_submissions)
        .where(identity_submissions: { status: :approved })
        .where.not(bonid: nil)
        .limit(3)
        .each do |user|
      puts "  #{user.bonid} - #{user.full_name}"
    end
    puts ""

    # Tourists with BonTouris
    puts "TOURISTS (BonTouris):"
    VisitorSubmission.approved.where.not(bonid: nil).limit(3).each do |visitor|
      puts "  #{visitor.bonid} - #{visitor.first_name} #{visitor.last_name} (#{visitor.nationality})"
    end
    puts ""

    # Persons with crime records
    puts "PERSONS WITH CRIME RECORDS:"
    PersonInvolvement.joins(:incident_report)
                     .where.not(bonid: nil)
                     .select(:bonid, :role, :status)
                     .distinct
                     .limit(5)
                     .each do |pi|
      puts "  #{pi.bonid} - Role: #{pi.role}, Status: #{pi.status || 'N/A'}"
    end
    puts ""

    # Get sample data for cURL commands
    sample_bonid = User.where.not(bonid: nil).first&.bonid ||
                   PersonInvolvement.where.not(bonid: nil).first&.bonid ||
                   "JM-1968-M-OUEST-P2334-217"

    sample_bontouris = VisitorSubmission.approved.where.not(bonid: nil).first&.bonid ||
                       "T-JS-1990-M-US-P-988455"

    sample_report = IncidentReport.first

    # Show example cURL commands
    puts "=" * 70
    puts "EXAMPLE CURL COMMANDS"
    puts "=" * 70
    puts ""

    puts "1. VERIFY IDENTITY (BonID - Citizen):"
    puts "-" * 70
    puts <<~CURL
      curl -X GET "http://localhost:3000/api/v1/identity/#{sample_bonid}" \\
        -H "X-Partner-Api-Key: #{raw_key}" \\
        -H "Authorization: Bearer #{token.token}" \\
        -H "Accept: application/json" | jq
    CURL
    puts ""

    puts "2. VERIFY IDENTITY (BonTouris - Tourist):"
    puts "-" * 70
    puts <<~CURL
      curl -X GET "http://localhost:3000/api/v1/identity/#{sample_bontouris}" \\
        -H "X-Partner-Api-Key: #{raw_key}" \\
        -H "Authorization: Bearer #{token.token}" \\
        -H "Accept: application/json" | jq
    CURL
    puts ""

    puts "3. QUICK STATUS CHECK:"
    puts "-" * 70
    puts <<~CURL
      curl -X GET "http://localhost:3000/api/v1/identity/#{sample_bonid}/status" \\
        -H "X-Partner-Api-Key: #{raw_key}" \\
        -H "Authorization: Bearer #{token.token}" \\
        -H "Accept: application/json" | jq
    CURL
    puts ""

    puts "4. CHECK CRIME STATUS:"
    puts "-" * 70
    puts <<~CURL
      curl -X GET "http://localhost:3000/api/v1/crime_status/#{sample_bonid}" \\
        -H "X-Partner-Api-Key: #{raw_key}" \\
        -H "Authorization: Bearer #{token.token}" \\
        -H "Accept: application/json" | jq
    CURL
    puts ""

    puts "5. SEARCH INCIDENT REPORTS:"
    puts "-" * 70
    puts <<~CURL
      curl -X GET "http://localhost:3000/api/v1/incident_reports?bonid=#{sample_bonid}" \\
        -H "X-Partner-Api-Key: #{raw_key}" \\
        -H "Authorization: Bearer #{token.token}" \\
        -H "Accept: application/json" | jq
    CURL
    puts ""

    puts "6. GET INCIDENT CERTIFICATE:"
    puts "-" * 70
    if sample_report
      puts <<~CURL
        curl -X GET "http://localhost:3000/api/v1/incident_reports/#{sample_report.uuid}/certificate" \\
          -H "X-Partner-Api-Key: #{raw_key}" \\
          -H "Authorization: Bearer #{token.token}" \\
          -H "Accept: application/json" | jq
      CURL
    else
      puts "No incident reports found. Create one first."
    end

    puts ""
    puts "=" * 70
    puts "CREDENTIALS GENERATED SUCCESSFULLY!"
    puts "=" * 70
    puts ""
    puts "=" * 70
    puts "QUICK REFERENCE"
    puts "=" * 70
    puts ""
    puts "IDENTITY VERIFICATION API:"
    puts "  GET /api/v1/identity/:bonid         - Full identity details"
    puts "  GET /api/v1/identity/:bonid/status  - Quick verification status"
    puts ""
    puts "CRIME STATUS API:"
    puts "  GET /api/v1/crime_status/:bonid              - Crime involvement"
    puts "  GET /api/v1/incident_reports?bonid=...       - Search reports"
    puts "  GET /api/v1/incident_reports/:id/certificate - Get certificate"
    puts ""
    puts "REQUIRED HEADERS:"
    puts "  X-Partner-Api-Key: #{raw_key}"
    puts "  Authorization: Bearer #{token.token}"
    puts "  Accept: application/json"
    puts ""
    puts "BONID FORMATS:"
    puts "  Citizens:  JM-1968-M-OUEST-P2334-217 (BonID)"
    puts "  Tourists:  T-JS-1990-M-US-P-988455   (BonTouris)"
    puts "  6-digits:  234217                    (Suffix lookup)"
    puts ""
    puts "DOCUMENTATION:"
    puts "  docs/api/README.md              - Developer guide"
    puts "  docs/api/CRIME_STATUS_API.md    - Full API reference"
    puts ""
    puts "=" * 70
  end
end
