# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Aktivite page tip", type: :request do
  before { sign_in create(:user, :with_address, :identity_verified) }

  it "tells citizens what to do if they don't recognize something, with working links" do
    get "/citizens/activity"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ou wè yon aktivite ou pa rekonèt?")
    expect(response.body).to include(%(href="/citizens/consents))
    expect(response.body).to include(%(href="/citizens/support))
    expect(response.body).not_to include("anrejistre epi yo pwoteje")
  end
end
