require 'rails_helper'

RSpec.describe "Admin::PartnerSchemas", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/admin/partner_schemas/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/admin/partner_schemas/show"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /approve" do
    it "returns http success" do
      get "/admin/partner_schemas/approve"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /reject" do
    it "returns http success" do
      get "/admin/partner_schemas/reject"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /deactivate" do
    it "returns http success" do
      get "/admin/partner_schemas/deactivate"
      expect(response).to have_http_status(:success)
    end
  end

end
