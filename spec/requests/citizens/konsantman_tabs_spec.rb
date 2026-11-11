# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Konsantman tabs", type: :request do
  let(:citizen) { create(:user, :with_address, :identity_verified) }
  before { sign_in citizen }

  def tab_links(body)
    body.scan(%r{<a[^>]*class="consent-section-tab[^"]*"[^>]*>}).join
  end

  it "shows both tabs on the requests page, with Requests active" do
    get "/citizens/transaction_consents"
    expect(response).to have_http_status(:ok)
    tabs = tab_links(response.body)
    expect(tabs).to include(%(href="/citizens/consents))
    expect(response.body).to match(%r{consent-section-tab is-active"[^>]*href="/citizens/transaction_consents|href="/citizens/transaction_consents[^>]*consent-section-tab is-active})
  end

  it "shows both tabs on the active access page, with Active access active" do
    get "/citizens/consents"
    expect(response).to have_http_status(:ok)
    expect(tab_links(response.body)).to include(%(href="/citizens/transaction_consents))
    expect(response.body).to match(%r{href="/citizens/consents[^>]*consent-section-tab is-active|consent-section-tab is-active"[^>]*href="/citizens/consents})
  end

  it "uses the right empty message on the active access page" do
    get "/citizens/consents"
    expect(response.body).to include("No partner has access to your data")
    expect(response.body).not_to include("No Active Requests")
  end

  it "keeps Konsantman highlighted in the sidebar on both pages" do
    %w[/citizens/transaction_consents /citizens/consents].each do |path|
      get path
      expect(response.body).to match(%r{nav-link active"[^>]*>\s*<i class="ri-shield-check-line"></i>\s*<span>Konsantman}m), path
    end
  end
end

RSpec.describe "Citizen sidebar highlighting", type: :request do
  let(:citizen) { create(:user, :with_address, :identity_verified) }
  before { sign_in citizen }

  def active_labels(body)
    body.scan(%r{class="nav-link active"[^>]*>\s*<i [^>]*></i>\s*<span>([^<]+)</span>}m).flatten
  end

  {
    "/citizens/dashboard" => "Dashboard",
    "/citizens/activity" => "Aktivite",
    "/citizens/transaction_consents" => "Konsantman",
    "/citizens/consents" => "Konsantman"
  }.each do |path, label|
    it "highlights only #{label} on #{path}" do
      get path
      expect(active_labels(response.body).uniq).to eq([ label ]) # sidebar renders twice (desktop + mobile)
    end
  end
end
