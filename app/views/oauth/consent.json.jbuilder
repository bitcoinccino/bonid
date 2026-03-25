# app/views/oauth/consent.json.jbuilder

json.partner do
  json.id @partner.id
  json.name @partner.name
  json.sector @partner.sector
  json.slug @partner.slug
  json.logo_url url_for(@partner.logo) if @partner.logo.attached?
end

json.requested_scopes @scopes
json.state @state
json.redirect_uri @redirect_uri if defined?(@redirect_uri) && @redirect_uri.present?

json.citizen @citizen_data

if @existing_grant.present?
  json.existing_grant do
    json.id @existing_grant.id
    json.status @existing_grant.status
    json.active @existing_grant.active?
    json.grant_token @existing_grant.grant_token
    json.granted_scopes (@existing_grant.granted_scopes.presence || @existing_grant.requested_scopes)
    json.granted_at @existing_grant.granted_at&.iso8601
    json.expires_at @existing_grant.expires_at&.iso8601
  end

  json.continue_url @continue_url
end

json.consent do
  json.approve_url decision_oauth_index_url(decision: :approve, format: :json)
  json.deny_url decision_oauth_index_url(decision: :deny, format: :json)
  json.expires_in 30.minutes.to_i
end

json.meta do
  json.timestamp Time.current.iso8601
  json.version "1.0"
  json.api "BonID Open Identity API"
end
