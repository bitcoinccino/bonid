require 'rails_helper'

RSpec.describe "Admin::ApiUsages", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/admin/api_usage/index"
      expect(response).to have_http_status(:success)
    end
  end

end
