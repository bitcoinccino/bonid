# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Citizens::NameChangeRequests", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActionDispatch::TestProcess::FixtureFile

  let(:citizen) { create(:user, :with_address, first_name: "Marie", last_name: "Pierre") }
  let(:partner) { create(:partner, :verified) }

  # Create a temp file for upload tests
  let(:upload_file) do
    Rack::Test::UploadedFile.new(
      StringIO.new("fake document content"),
      "application/pdf",
      original_filename: "marriage_certificate.pdf"
    )
  end

  before do
    sign_in citizen, scope: :citizen
  end

  describe "GET /citizens/name_change_requests/new" do
    context "when citizen has a verified identity" do
      before do
        create(:identity_submission, :approved, user: citizen, partner: partner)
      end

      it "renders the name change request form" do
        get new_citizens_name_change_request_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when citizen is NOT verified" do
      it "redirects with an alert" do
        get new_citizens_name_change_request_path
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "POST /citizens/name_change_requests" do
    let!(:submission) { create(:identity_submission, :approved, user: citizen, partner: partner) }

    let(:valid_params) do
      {
        name_change_request: {
          new_first_name: "Marie-Anne",
          new_middle_name: "Claudette",
          new_last_name: "Dupont",
          reason: "marriage",
          supporting_document: upload_file
        }
      }
    end

    context "with valid parameters" do
      it "creates a name change request" do
        expect {
          post citizens_name_change_requests_path, params: valid_params
        }.to change(NameChangeRequest, :count).by(1)
      end

      it "snapshots the citizen's current name" do
        post citizens_name_change_requests_path, params: valid_params

        request = NameChangeRequest.last
        expect(request.old_first_name).to eq("Marie")
        expect(request.old_last_name).to eq("Pierre")
      end

      it "stores the requested new name" do
        post citizens_name_change_requests_path, params: valid_params

        request = NameChangeRequest.last
        expect(request.new_first_name).to eq("Marie-Anne")
        expect(request.new_middle_name).to eq("Claudette")
        expect(request.new_last_name).to eq("Dupont")
      end

      it "creates the request with pending status" do
        post citizens_name_change_requests_path, params: valid_params
        expect(NameChangeRequest.last).to be_pending
      end

      it "redirects to the dashboard with a success notice" do
        post citizens_name_change_requests_path, params: valid_params
        expect(response).to redirect_to(citizens_dashboard_path)
      end

      it "attaches the supporting document" do
        post citizens_name_change_requests_path, params: valid_params
        expect(NameChangeRequest.last.supporting_document).to be_attached
      end
    end

    context "with missing required fields" do
      it "does not create a request without new_first_name" do
        invalid_params = valid_params.deep_dup
        invalid_params[:name_change_request][:new_first_name] = ""

        expect {
          post citizens_name_change_requests_path, params: invalid_params
        }.not_to change(NameChangeRequest, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not create a request without a reason" do
        invalid_params = valid_params.deep_dup
        invalid_params[:name_change_request][:reason] = ""

        expect {
          post citizens_name_change_requests_path, params: invalid_params
        }.not_to change(NameChangeRequest, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when citizen is NOT verified" do
      before do
        IdentitySubmission.destroy_all
      end

      it "redirects instead of creating the request" do
        post citizens_name_change_requests_path, params: valid_params
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
