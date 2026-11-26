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

  describe "share link (?ref=)" do
    let!(:ambassador) { WaitlistSignup.create!(email: "rose@example.com", first_name: "Rose", signup_type: "citizen") }

    it "opens the form with an 'invited by' banner and carries the code" do
      get enskri_path(ref: ambassador.referral_code, lang: "ht")
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("Envite pa Rose", 'data-auto-open="1"', %(value="#{ambassador.referral_code}"))
    end

    it "ignores an unknown code" do
      get enskri_path(ref: "XX-NOPE00")
      expect(response.body).to include('data-auto-open="0"')
      expect(response.body).not_to include("Invited by")
    end

    it "credits the referrer and shows the count on their confirmation page" do
      post_signup({ referred_by_code: ambassador.referral_code })
      expect(WaitlistSignup.find_by(email: "jean@example.com").referrer).to eq(ambassador)

      get enskri_confirmation_path(ref: ambassador.referral_code, lang: "fr")
      expect(CGI.unescapeHTML(response.body)).to include("1 personne s'est inscrite avec votre lien")
    end
  end

  it "remembers the language the person signed up in" do
    post_signup({}, lang: "en")
    expect(WaitlistSignup.find_by(email: "jean@example.com").locale).to eq("en")
  end

  it "saves a US diaspora signup's state and city" do
    post_signup({ commune_id: nil, diaspora: "1", country_of_residence: "US",
                  residence_state: "FL", residence_city: "Miami" })
    expect(JSON.parse(response.body)["ok"]).to be(true)
    signup = WaitlistSignup.find_by(email: "jean@example.com")
    expect([signup.residence_state, signup.residence_city]).to eq(["FL", "Miami"])
  end

  it "shows the State and City fields in the form" do
    get enskri_path(lang: "fr")
    body = CGI.unescapeHTML(response.body)
    expect(body).to include('id="modal_us_state"', "Florida", 'list="modal-us-city-list"', "Tapez le nom de votre ville")
  end

  it "returns a state's city suggestions" do
    get "/enskri/us_cities", params: { state: "FL" }
    cities = JSON.parse(response.body)
    expect(cities.first).to eq("Miami")
    expect(cities).to include("Hialeah")
    expect(response.headers["Cache-Control"]).to include("public")
  end

  it "reports a duplicate email in the visitor's language" do
    post_signup
    post_signup
    body = JSON.parse(response.body)
    expect(body["ok"]).to be(false)
    expect(body["error"]).to eq("Cet e-mail est déjà inscrit.")
  end

  describe "confirmation page" do
    let(:signup) do
      WaitlistSignup.create!(first_name: "Rose", email: "rosalind@yahoo.com", signup_type: "citizen", commune: commune)
    end

    {
      "ht" => ["Ou sou lis la!", "Pataje sou WhatsApp", "Kopye lyen"],
      "fr" => ["Vous êtes inscrit !", "Partager sur WhatsApp", "Copier le lien"],
      "en" => ["You're on the list!", "Share on WhatsApp", "Copy link"]
    }.each do |lang, (title, whatsapp, copy)|
      it "renders in #{lang} only" do
        get enskri_confirmation_path(ref: signup.referral_code, lang: lang)
        body = CGI.unescapeHTML(response.body)
        expect(body).to include(title, whatsapp, copy)
        expect(body).to include("r***d@yahoo.com")
        expect(body).to include("/enskri?ref=#{signup.referral_code}")
        others = %w[ht fr en] - [lang]
        titles = { "ht" => "Ou sou lis la!", "fr" => "Vous êtes inscrit !", "en" => "You're on the list!" }
        others.each { |o| expect(body).not_to include(titles[o]) }
      end
    end

    it "sends the visitor to the confirmation page in their language" do
      post_signup({}, lang: "en")
      expect(JSON.parse(response.body)["redirect"]).to include("/enskri/confirmation", "lang=en")
    end
  end
end
