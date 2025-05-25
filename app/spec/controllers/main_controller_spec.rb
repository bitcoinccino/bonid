RSpec.describe MainController, type: :controller do
  describe "GET #start" do
    let!(:partner) { Partner.create!(name: "Valid Partner", slug: "valid-partner", verified_at: Time.current) }

    it "sets session for valid partner" do
      get :start, params: { partner: "valid-partner" }
      expect(session[:bonid_partner_id]).to eq(partner.id)
    end

    it "redirects with alert for unverified partner" do
      Partner.create!(name: "Unverified", slug: "unverified", verified_at: nil)
      get :start, params: { partner: "unverified" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Invalid or unverified partner.")
    end

    it "redirects with alert for missing partner param" do
      get :start
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Missing partner parameter.")
    end
  end
end
