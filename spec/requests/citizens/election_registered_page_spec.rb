# frozen_string_literal: true

require "rails_helper"

# "Mes élections" page for a citizen who is already registered: hero with
# status + voter number, "where & when", receipt actions, verification +
# collapsed history / administrative details.
RSpec.describe "Election registration page — registered state", type: :request do
  let!(:citizen)  { create(:user, is_diaspora: false, preferred_locale: "fr") }
  let!(:election) { create(:bonvote_election) }
  let!(:record) do
    create(:voter_eligibility_record, bonvote_election: election, user: citizen,
           registered_at: Time.zone.local(2026, 4, 20, 11, 2))
  end

  before do
    sign_in citizen, scope: :citizen
    get citizens_election_enrollment_path
  end

  it "shows the hero: election, registered status and voter number with copy" do
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("voter-hero")
    expect(response.body).to include(CGI.escapeHTML(election.title))
    expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.election.enrollment.registered_title", locale: :fr)))
    expect(response.body).to include(record.voter_reference)
    expect(response.body).to include('class="voter-id-card__copy"')
  end

  it "shows the election name only once (hero, not the page subtitle)" do
    expect(response.body.scan(CGI.escapeHTML(election.title)).size).to eq(1)
    expect(response.body).not_to include('class="ballot-subtitle')
  end

  it "groups venue info under Where & when, with admin details collapsed" do
    expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.election.enrollment.where_when", locale: :fr)))
    expect(response.body).to match(%r{<details class="voter-details">\s*<summary>#{Regexp.escape(CGI.escapeHTML(I18n.t("citizen_portal.election.enrollment.admin_details", locale: :fr)))}})
  end

  it "keeps receipt actions and moves channel/timestamp into the history" do
    expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.election.enrollment.download_receipt", locale: :fr)))
    expect(response.body).to include("voter-details--history")
    expect(response.body).to include("voter-timeline")
    expect(response.body).not_to include("voter-status-header")
  end
end
