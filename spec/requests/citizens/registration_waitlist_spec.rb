# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Citizen sign-up gate (/signup)", type: :request do
  let(:commune) { (Commune.first || create(:commune)).tap { |c| c.update!(code: "HT0112") } }

  def register(params)
    post citizen_registration_path, params: params.merge(citizen: { email: "New.Citizen@example.com" })
    User.find_by(email: "new.citizen@example.com")
  end

  describe "GET /signup" do
    it "opens for a verified partner" do
      get signup_path(partner: create(:partner, :verified).slug)
      expect(response).to have_http_status(:ok)
    end

    it "opens for a launched commune" do
      commune.update!(launched: true)
      get signup_path(commune: "HT0112")
      expect(response).to have_http_status(:ok)
    end

    it "says which language emails will be in, with a link to change it" do
      commune.update!(launched: true)
      get signup_path(commune: "HT0112", lang: "fr")
      expect(response.body).to include("Nous vous écrirons en français", "Modifier")
      get signup_path(commune: "HT0112", lang: "en")
      expect(response.body).to include("We&#39;ll email you in English")
    end

    it "saves the sign-up page's language as the account language (emails use it)" do
      commune.update!(launched: true)
      get signup_path(commune: "HT0112", lang: "fr")
      user = register(commune: "HT0112")
      expect(user.preferred_locale).to eq("fr")
    end

    it "opens for an available invite code, typed loosely" do
      InviteCode.create!(code: "DEL-7KQ2XA", code_type: "personal")
      get signup_path(invite: "del7kq2xa")
      expect(response).to have_http_status(:ok)
    end

    it "sends a not-launched commune to the waitlist" do
      get signup_path(commune: "HT0112")
      expect(URI(response.location).path).to eq("/enskri")
    end

    it "sends a bare visit to the waitlist, not the partner list" do
      get signup_path
      expect(URI(response.location).path).to eq("/enskri")
    end
  end

  describe "POST /signup" do
    it "registers under the partner and converts the waitlist entry" do
      partner = create(:partner, :verified)
      signup  = WaitlistSignup.create!(email: "new.citizen@example.com", signup_type: "citizen", status: "invited")

      user = register(partner: partner.slug)

      expect(user.partner).to eq(partner)
      expect(signup.reload.status).to eq("converted")
    end

    it "registers directly (no partner) from a launched commune" do
      commune.update!(launched: true)
      user = register(commune: "HT0112")
      expect(user).to be_present
      expect(user.partner_id).to be_nil
      expect(cookies[:pending_consent]).to be_blank
    end

    it "redeems an invite code once the account exists" do
      code = InviteCode.create!(code: "DEL-7KQ2XA", code_type: "personal", max_uses: 1)
      user = register(invite: "DEL-7KQ2XA")
      expect(user).to be_present
      expect(code.reload.uses_count).to eq(1)
    end

    it "uses a verified partner attached to the invite code" do
      partner = create(:partner, :verified)
      InviteCode.create!(code: "DEL-7KQ2XA", code_type: "partner", partner: partner, max_uses: 5)
      expect(register(invite: "DEL-7KQ2XA").partner).to eq(partner)
    end

    it "refuses without a green light" do
      expect(register({})).to be_nil
      expect(URI(response.location).path).to eq("/enskri")
    end
  end
end
