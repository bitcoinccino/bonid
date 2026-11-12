# frozen_string_literal: true

# Plain-English names for permission codes, so citizens see "Phone number"
# instead of "phone" and "Photo and face check" instead of "identity:verify".
module ConsentScopeLabelsHelper
  SCOPE_LABELS = {
    "profile"                         => "Name, date of birth and photo",
    "email"                           => "Email address",
    "phone"                           => "Phone number",
    "address"                         => "Home address",
    "identity:verify"                 => "Photo and face check",
    "verifications:verify_identity"   => "Whether your BonID is verified",
    "identity:details"                => "All your BonID information",
    "civil"                           => "Birth and family records",
    "health"                          => "Health information",
    "physical"                        => "Physical description",
    "tax"                             => "Tax ID number",
    "emergency_contacts"              => "Emergency contacts",
    "social"                          => "Social media accounts",
    "crime:status"                    => "Criminal record check",
    "crime:reports"                   => "Police reports about you",
    "crime:certificate"               => "Police record certificate",
    "crime:full"                      => "Full police record"
  }.freeze

  # Technical scopes that don't share any information on their own.
  HIDDEN_SCOPES = %w[openid].freeze

  # Localized under citizen_portal.consents.scope_labels.* (":" → "_" in
  # keys); SCOPE_LABELS is the English fallback.
  def consent_scope_label(scope)
    fallback = SCOPE_LABELS.fetch(scope.to_s) { scope.to_s.tr(":_", "  ").capitalize }
    I18n.t("citizen_portal.consents.scope_labels.#{scope.to_s.tr(':', '_')}", default: fallback)
  end

  def visible_consent_scopes(scopes)
    Array(scopes).map(&:to_s) - HIDDEN_SCOPES
  end
end
