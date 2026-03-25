# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::NameChangeRequests", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin_user) { create(:admin_user) }
  let(:citizen) { create(:user, first_name: "Marie", last_name: "Pierre") }

  before do
    sign_in admin_user, scope: :admin_user
    # Skip guidelines confirmation check (session-based guard in Admin::ApplicationController)
    allow_any_instance_of(Admin::NameChangeRequestsController)
      .to receive(:ensure_guidelines_confirmed).and_return(true)
  end

  describe "GET /admin/name_change_requests" do
    it "returns http success" do
      get admin_name_change_requests_path
      expect(response).to have_http_status(:ok)
    end

    it "lists pending requests" do
      create(:name_change_request, user: citizen)
      get admin_name_change_requests_path
      expect(response.body).to include(citizen.email)
    end

    it "filters by status" do
      create(:name_change_request, :pending, user: citizen)
      create(:name_change_request, :approved, user: create(:user))

      get admin_name_change_requests_path(status: :pending)
      expect(response.body).to include(citizen.email)
    end
  end

  describe "GET /admin/name_change_requests/:id" do
    let!(:request_record) { create(:name_change_request, user: citizen) }

    it "returns http success" do
      get admin_name_change_request_path(request_record)
      expect(response).to have_http_status(:ok)
    end

    it "shows the name comparison" do
      get admin_name_change_request_path(request_record)
      expect(response.body).to include(request_record.old_first_name)
      expect(response.body).to include(request_record.new_first_name)
    end
  end

  describe "PATCH /admin/name_change_requests/:id/approve" do
    let!(:request_record) { create(:name_change_request, user: citizen) }

    it "approves the request and updates the citizen's name" do
      patch approve_admin_name_change_request_path(request_record),
            params: { admin_note: "Documents verified." }

      request_record.reload
      expect(request_record).to be_approved
      expect(request_record.reviewed_by).to eq(admin_user)
      expect(request_record.reviewed_at).to be_present

      citizen.reload
      expect(citizen.first_name).to eq(request_record.new_first_name)
      expect(citizen.last_name).to eq(request_record.new_last_name)
    end

    it "sends an approval email" do
      expect {
        patch approve_admin_name_change_request_path(request_record)
      }.to have_enqueued_mail(UserMailer, :name_change_approved)
    end

    it "redirects to the index with a success notice" do
      patch approve_admin_name_change_request_path(request_record)
      expect(response).to redirect_to(admin_name_change_requests_path)
    end
  end

  describe "PATCH /admin/name_change_requests/:id/reject" do
    let!(:request_record) { create(:name_change_request, user: citizen) }

    context "with a rejection reason" do
      it "rejects the request" do
        patch reject_admin_name_change_request_path(request_record),
              params: { rejection_reason: "Document is illegible.", admin_note: "Blurry scan." }

        request_record.reload
        expect(request_record).to be_rejected
        expect(request_record.rejection_reason).to eq("Document is illegible.")
        expect(request_record.reviewed_by).to eq(admin_user)
      end

      it "does NOT change the citizen's name" do
        original_first = citizen.first_name
        original_last = citizen.last_name

        patch reject_admin_name_change_request_path(request_record),
              params: { rejection_reason: "Invalid document." }

        citizen.reload
        expect(citizen.first_name).to eq(original_first)
        expect(citizen.last_name).to eq(original_last)
      end

      it "sends a rejection email" do
        expect {
          patch reject_admin_name_change_request_path(request_record),
                params: { rejection_reason: "Invalid document." }
        }.to have_enqueued_mail(UserMailer, :name_change_rejected)
      end
    end

    context "without a rejection reason" do
      it "redirects back to show with an alert" do
        patch reject_admin_name_change_request_path(request_record),
              params: { rejection_reason: "" }

        expect(response).to redirect_to(admin_name_change_request_path(request_record))
      end
    end
  end
end
