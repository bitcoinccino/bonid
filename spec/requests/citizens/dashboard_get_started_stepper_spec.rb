# frozen_string_literal: true

require "rails_helper"

# Dashboard "get started" (no request sent yet): vertical stepper with the
# finished step collapsed and the current step open with its button.
RSpec.describe "Dashboard get-started stepper", type: :request do
  before do
    allow(Geocoder).to receive(:search).and_return([])
    sign_in citizen, scope: :citizen
    get citizens_dashboard_path
  end

  context "when the profile isn't finished" do
    let(:citizen) { create(:user, is_diaspora: false, preferred_locale: "ht") }

    it "opens step 1 with the profile button" do
      expect(response.body).to include('class="gs-step is-current" aria-current="step"')
      expect(response.body.index("gs-step is-current")).to be < response.body.index("gs-step is-next")
      expect(response.body).to include(edit_citizens_profile_path)
      expect(response.body).not_to include("gs-step is-done")
    end
  end

  context "when the profile is complete" do
    let(:citizen) { create(:user, :profile_complete, is_diaspora: false, preferred_locale: "ht") }

    before do
      citizen.photo.attach(io: StringIO.new("x"), filename: "p.jpg", content_type: "image/jpeg")
      get citizens_dashboard_path
    end

    it "collapses step 1 and opens step 2 with the documents and the button" do
      expect(response.body).to include("gs-step is-done")
      expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.dashboard.get_started.selfie_label", locale: :ht)))
      expect(response.body).to include(new_citizens_identity_submission_path)
    end
  end
end
