# frozen_string_literal: true

require "rails_helper"

# Guards against messages that ignore the page language: a literal string in
# a flash/JSON error or validation shows in one language no matter whether
# the citizen is browsing in Kreyòl, French or English. Use t("alerts.…") in
# controllers and I18n.t("alerts.validation.…") in models instead.
RSpec.describe "Citizen-facing messages are translated" do
  # notice: "…" / alert: "…" / flash[:x] = "…" / flash.now[:x] = "…" / error: "…"
  FLASH_LITERAL = /(?:\b(?:notice|alert|error)\s*:|flash(?:\.now)?\[:\w+\]\s*=)\s*["']/
  ERRORS_LITERAL = /errors\.add\([^,]+,\s*["']/

  CONTROLLER_GLOBS = %w[
    app/controllers/citizens/**/*.rb
    app/controllers/public/**/*.rb
  ].freeze

  CITIZEN_MODELS = %w[
    app/models/identity_submission.rb
    app/models/family_member.rb
    app/models/emergency_contact.rb
    app/models/local_contact.rb
    app/models/election_candidate_endorsement.rb
    app/models/visitor_submission.rb
    app/models/concerns/document_validations.rb
    app/models/concerns/record_schemas/nif_registration_schema.rb
    app/models/concerns/record_schemas/business_registration_schema.rb
    app/models/concerns/record_schemas/fermage_schema.rb
    app/models/concerns/record_schemas/ras_ir_declaration_schema.rb
    app/models/concerns/record_schemas/tca_declaration_schema.rb
    app/models/concerns/record_schemas/patente_declaration_schema.rb
  ].freeze

  # Machine-readable codes consumed by JS, not shown to people.
  ALLOWED = [
    %r{app/controllers/citizens/dgi_controller\.rb:.*error: "invalid"}
  ].freeze

  def offenders(files, pattern)
    files.flat_map do |file|
      File.readlines(Rails.root.join(file), encoding: "UTF-8").each_with_index.filter_map do |line, i|
        next if line.lstrip.start_with?("#")
        next unless line.match?(pattern)

        hit = "#{file}:#{i + 1}: #{line.strip}"
        hit unless ALLOWED.any? { |re| hit.match?(re) }
      end
    end
  end

  it "citizen and public controllers use t() for flashes and JSON errors" do
    files = CONTROLLER_GLOBS.flat_map { |g| Dir[Rails.root.join(g)] }
                            .map { |f| Pathname(f).relative_path_from(Rails.root).to_s }
    files << "app/controllers/oauth_controller.rb"

    hits = offenders(files, FLASH_LITERAL)
    # OAuth token/userinfo errors are protocol codes for partner apps (RFC 6749).
    hits.reject! { |h| h.start_with?("app/controllers/oauth_controller.rb") && h.include?("render json:") }

    expect(hits).to be_empty, "Hardcoded messages (use t(\"alerts.…\")):\n#{hits.join("\n")}"
  end

  it "citizen-facing models use I18n.t() for validation messages" do
    hits = offenders(CITIZEN_MODELS, ERRORS_LITERAL)
    expect(hits).to be_empty, "Hardcoded validation messages (use I18n.t(\"alerts.validation.…\")):\n#{hits.join("\n")}"
  end
end
