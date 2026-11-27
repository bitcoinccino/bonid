# frozen_string_literal: true

require "rails_helper"

# Bell: each notification stays unread until the citizen opens it, or
# presses "Mark all as read". Opening the bell / the Activité page changes
# nothing, and the citizen's own actions never count.
RSpec.describe "Citizen notification bell", type: :request do
  let!(:citizen) { create(:user, is_diaspora: false) }
  let(:counter)  { Citizens::AlertCounter.new(citizen.reload) }

  before do
    citizen.update_columns(notifications_seen_at: 2.days.ago)
    sign_in citizen, scope: :citizen
  end

  def key_for(grant)
    CitizenActivityEvent.events_from_consent_grant(grant.reload).last.notification_key
  end

  describe "what counts" do
    it "counts a partner asking for access" do
      create(:consent_grant, citizen: citizen) # pending
      expect(counter.total).to eq(1)
    end

    it "does not count the citizen's own grant or removal" do
      g = create(:consent_grant, citizen: citizen)
      g.grant!(scopes: g.requested_scopes)
      expect(counter.total).to eq(0)

      g.revoke!(reason: "Citizen revoked from dashboard")
      expect(Citizens::AlertCounter.new(citizen.reload).total).to eq(0)
    end
  end

  describe "opening one notification" do
    it "marks only that one read and goes to the consents page" do
      a = create(:consent_grant, citizen: citizen)
      create(:consent_grant, citizen: citizen)
      expect(counter.total).to eq(2)

      post citizens_notification_open_path(key: key_for(a))

      expect(response).to redirect_to(%r{/citizens/consents})
      expect(Citizens::AlertCounter.new(citizen.reload).total).to eq(1)
    end

    it "ignores keys that aren't notification keys" do
      post citizens_notification_open_path(key: "../../admin")
      expect(response).to redirect_to(%r{/citizens/activity})
      expect(citizen.notification_reads.count).to eq(0)
    end
  end

  describe "mark all as read" do
    it "clears every unread notification and goes back" do
      create(:consent_grant, citizen: citizen)
      expect(counter.total).to be_positive

      post citizens_notifications_seen_path, headers: { "HTTP_REFERER" => "/citizens/activity" }

      expect(response).to redirect_to("/citizens/activity")
      expect(Citizens::AlertCounter.new(citizen.reload).total).to eq(0)
    end
  end

  it "visiting Activité does not mark anything read" do
    create(:consent_grant, citizen: citizen)
    get citizens_activity_path
    expect(Citizens::AlertCounter.new(citizen.reload).total).to eq(1)
  end

  it "shows the unread item as a button and a Mark all as read control" do
    create(:consent_grant, citizen: citizen)
    get citizens_activity_path
    expect(response.body).to include("/citizens/notifications/open")
    expect(response.body).to include("/citizens/notifications/seen")
  end

  it "requires a signed-in citizen" do
    sign_out citizen
    post citizens_notifications_seen_path
    expect(response).not_to have_http_status(:no_content)
    expect(response).not_to redirect_to("/citizens/activity")
  end
end
