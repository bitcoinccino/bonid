# frozen_string_literal: true

require "rails_helper"

# Opening the topbar bell marks notifications as seen, so the unread badge
# clears instead of staying until the citizen visits the Activité page.
RSpec.describe "Citizen notifications — mark seen", type: :request do
  let!(:citizen) { create(:user, is_diaspora: false) }

  before { sign_in citizen, scope: :citizen }

  it "stamps notifications_seen_at and returns no content" do
    citizen.update_columns(notifications_seen_at: 2.days.ago)

    post citizens_notifications_seen_path
    expect(response).to have_http_status(:no_content)
    expect(citizen.reload.notifications_seen_at).to be_within(5.seconds).of(Time.current)
  end

  it "brings the bell's unread total back to zero" do
    citizen.update_columns(notifications_seen_at: 2.days.ago)
    create(:consent_grant, citizen: citizen) # newer than seen_at → counts
    expect(Citizens::AlertCounter.new(citizen.reload).total).to be_positive

    post citizens_notifications_seen_path
    expect(Citizens::AlertCounter.new(citizen.reload).total).to eq(0)
  end

  it "requires a signed-in citizen" do
    sign_out citizen
    post citizens_notifications_seen_path
    expect(response).not_to have_http_status(:no_content)
  end
end
