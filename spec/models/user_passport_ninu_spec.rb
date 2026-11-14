# frozen_string_literal: true

require "rails_helper"

# Profile wizard: choosing Passport requires a 10-digit NINU. Other saves
# (no enforce flag) stay unaffected for existing passport holders.
RSpec.describe User, "passport NINU on the profile wizard", type: :model do
  let(:user) { create(:user) }

  before { user.assign_attributes(id_type: "passport", id_number: "R10772334") }

  it "accepts a NINU as a passport number format" do
    expect(CinNumberValidator.valid?("0123456789", "passport")).to be(true)
  end

  it "requires a NINU when the wizard enforces it" do
    user.enforce_passport_ninu = true
    user.ninu = ""

    expect(user).not_to be_valid
    expect(user.errors[:ninu]).to include(I18n.t("alerts.validation.user.ninu_required"))
  end

  it "rejects a NINU that isn't 10 digits" do
    user.enforce_passport_ninu = true
    user.ninu = "12345"

    expect(user).not_to be_valid
    expect(user.errors[:ninu]).to include(I18n.t("alerts.validation.user.ninu_format"))
  end

  it "accepts 10 digits and strips spaces" do
    user.enforce_passport_ninu = true
    user.ninu = "01234 56789"

    expect(user).to be_valid
    expect(user.ninu).to eq("0123456789")
  end

  it "doesn't block other saves without the flag" do
    user.ninu = ""

    expect(user.errors[:ninu]).to be_empty if user.valid?
    expect(user.errors[:ninu]).to be_empty
  end

  it "doesn't ask CIN holders for a NINU" do
    user.assign_attributes(id_type: "cin", ninu: "")
    user.enforce_passport_ninu = true
    user.valid?

    expect(user.errors[:ninu]).to be_empty
  end

  it "uses the NINU as the passport's ID number" do
    user.enforce_passport_ninu = true
    user.assign_attributes(id_number: "2345692560", ninu: "0123456789")

    expect(user).to be_valid
    expect(user.id_number).to eq("0123456789")
  end
end
