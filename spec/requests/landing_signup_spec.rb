# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Waitlist sign-up (/enskri)", type: :request do
  # test DB may hold reference rows
  let(:commune) { (Commune.first || create(:commune)).tap { |c| c.update!(code: "HT0112") } }

  def post_signup(attrs = {}, lang: "fr")
    post enskri_signup_path(lang: lang),
         params: { waitlist_signup: { first_name: "Jean", last_name: "Pierre",
                                      email: "jean@example.com", signup_type: "citizen",
                                      commune_id: commune.id }.merge(attrs) },
         as: :json
  end

  it "sends a not-yet-launched commune to the confirmation page" do
    post_signup
    body = JSON.parse(response.body)
    expect(body["ok"]).to be(true)
    expect(body["redirect"]).to include("/enskri/confirmation")
  end

  it "sends a launched commune on to account creation with its commune code" do
    commune.update!(launched: true)
    post_signup
    body = JSON.parse(response.body)
    expect(body["ok"]).to be(true)
    expect(body["redirect"]).to eq("/signup?commune=HT0112&lang=fr")
  end

  it "sends an invite-code holder to /signup with the code, without redeeming it yet" do
    code = InviteCode.create!(code: "DEL-7KQ2XA", code_type: "personal", max_uses: 1)
    post_signup({ invite_code_used: "del 7kq2xa" })
    body = JSON.parse(response.body)
    expect(body["redirect"]).to eq("/signup?invite=DEL-7KQ2XA&lang=fr")
    expect(code.reload.uses_count).to eq(0)
  end

  it "rejects an unknown invite code" do
    post_signup({ invite_code_used: "NOPE-123456" })
    body = JSON.parse(response.body)
    expect(body["ok"]).to be(false)
  end

  it "reports a duplicate email in the visitor's language" do
    post_signup
    post_signup
    body = JSON.parse(response.body)
    expect(body["ok"]).to be(false)
    expect(body["error"]).to eq("Cet e-mail est déjà inscrit.")
  end
end
