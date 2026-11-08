# frozen_string_literal: true

require "rails_helper"

# The main navbar has no login links; partners reach their portal from the
# footer or the partner application page.
RSpec.describe "Partner entry points", type: :request do
  it "the footer links to partner login and the partner application" do
    get root_path
    footer = response.body[%r{<footer.*?</footer>}m]

    expect(footer).to include(partners_login_path, new_partner_path)
    expect(footer).to include("Partner Login", "Become a Partner")
  end

  it "the partner application page links to partner login" do
    get new_partner_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Already a partner?")
    expect(response.body).to include(partners_login_path)
  end
end
