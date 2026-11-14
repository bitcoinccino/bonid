# frozen_string_literal: true

require "rails_helper"

# Personal info on the profile form: identity fields first, then what the
# citizen can change; one lock note instead of a hint under every field.
RSpec.describe "Profile personal fields", type: :request do
  let!(:citizen) { create(:user, is_diaspora: false, preferred_locale: "fr") }

  before { sign_in citizen, scope: :citizen }

  it "groups identity fields before the editable ones" do
    get edit_citizens_profile_path

    body = response.body
    identity = body.index(CGI.escapeHTML(I18n.t("citizen_portal.profile.personal.group_identity", locale: :fr)))
    editable = body.index(CGI.escapeHTML(I18n.t("citizen_portal.profile.personal.group_editable", locale: :fr)))
    expect(identity).to be < editable
    expect(body.index('id="citizen_phone"')).to be > editable
    expect(body).to include("haiti_flag")
  end

  context "when the identity is verified" do
    before { create(:identity_submission, :approved, user: citizen) }

    it "shows one lock note and locks the identity group, without a hint per field" do
      get edit_citizens_profile_path

      expect(response.body).to include("pf-lock-note", "pf-locked")
      expect(response.body).not_to include(CGI.escapeHTML(I18n.t("citizen_portal.profile.locked_hint", locale: :fr)))
    end
  end

  it "groups the ID step into document and place of birth" do
    get edit_citizens_profile_path

    body = response.body
    heading = ->(key) { body.index(%(<h3 class="pf-group-title">#{CGI.escapeHTML(I18n.t("citizen_portal.profile.id.#{key}", locale: :fr))}</h3>)) }
    doc   = heading.("group_document")
    birth = heading.("group_birth")
    expect(doc).to be < birth
    expect(body.index("user[birth_department_id]")).to be > birth
  end

  it "drops the repetitive address cascade hints" do
    get edit_citizens_profile_path

    expect(response.body).not_to include(CGI.escapeHTML(I18n.t("citizen_portal.profile.address.department_hint", locale: :fr)))
  end

  it "shows the review as label-over-value cells with a friendly empty text" do
    get edit_citizens_profile_path

    expect(response.body).to include('class="review-item" data-review-key="full_name"')
    expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.profile.review.empty", locale: :fr)))
  end

  it "labels every wizard button with text, never a raw translation hash" do
    get edit_citizens_profile_path

    expect(response.body).not_to include("{:")
    expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.profile.steps.review", locale: :fr)))
  end
end
