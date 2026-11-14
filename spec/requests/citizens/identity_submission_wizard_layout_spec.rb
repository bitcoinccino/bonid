# frozen_string_literal: true

require "rails_helper"

# Verification wizard: one short note instead of a yellow "Important" box
# per step, working step buttons, and a review that follows step order.
RSpec.describe "Identity submission wizard layout", type: :request do
  let(:citizen) { create(:user, :profile_complete, preferred_locale: "fr") }

  before do
    citizen.photo.attach(io: StringIO.new("fake"), filename: "photo.jpg", content_type: "image/jpeg")
    sign_in citizen, scope: :citizen
    allow(Geocoder).to receive(:search).and_return([])
    get new_citizens_identity_submission_path
  end

  it "renders without raw translation hashes and with the short note only once" do
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("{:")
    expect(response.body).not_to include("FEF3C7")
    expect(response.body.scan("pf-lock-note").size).to eq(1)
  end

  it "orders the review like the steps, each Modifier going to its own step" do
    body = response.body
    steps = body.scan(/class="review-edit" data-action="click->wizard#goToStep" data-step="(\d)"/).flatten
    expect(steps).to eq(%w[1 2 3 4])
    expect(body).to include(CGI.escapeHTML(I18n.t("citizen_portal.submission.review.provide_in_step4", locale: :fr)))
  end
end
