# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Correction request form", type: :request do
  let(:citizen) { create(:user, is_diaspora: false, preferred_locale: "fr") }

  before do
    create(:identity_submission, :approved, user: citizen)
    sign_in citizen, scope: :citizen
  end

  it "asks what to correct, with names and date of birth, pre-filled with current values" do
    get new_citizens_name_change_request_path

    expect(response).to have_http_status(:ok)
    %w[first_name middle_name last_name dob].each do |f|
      expect(response.body).to include(%(value="#{f}"))
    end
    expect(response.body).to include(%(value="#{citizen.first_name}"))
  end

  it "creates a date-of-birth-only correction" do
    expect {
      post citizens_name_change_requests_path, params: {
        name_change_request: {
          change_fields: %w[dob], new_dob: "1985-03-15", reason: "error",
          new_first_name: "ignored", new_last_name: "ignored",
          supporting_document: fixture_file_upload(Rails.root.join("spec/fixtures/files/cin_front.png"), "image/png")
        }
      }
    }.to change(NameChangeRequest, :count).by(1)

    req = NameChangeRequest.last
    expect(req.new_dob).to eq(Date.new(1985, 3, 15))
    expect(req.new_first_name).to eq(citizen.first_name)
  end
end
