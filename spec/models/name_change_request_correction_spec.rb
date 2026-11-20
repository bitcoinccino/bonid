# frozen_string_literal: true

require "rails_helper"

# Correction requests: tick what changes (names and/or date of birth); the
# change is applied once the citizen's re-verification is approved.
RSpec.describe NameChangeRequest, "corrections", type: :model do
  let(:user) { create(:user, first_name: "Davidson", last_name: "Louis", dob: Date.new(1988, 6, 17)) }

  def build_request(**attrs)
    build(:name_change_request, user: user, reason: "error",
          new_first_name: user.first_name, new_last_name: user.last_name, **attrs)
  end

  it "keeps unticked fields at their current value" do
    req = build_request(change_fields: %w[dob], new_first_name: "Typed by mistake", new_dob: Date.new(1987, 6, 17))
    req.valid?

    expect(req.new_first_name).to eq("Davidson")
    expect(req.changed_fields).to eq(%w[dob])
  end

  it "refuses a request where nothing changes" do
    req = build_request(change_fields: %w[first_name])

    expect(req).not_to be_valid
    expect(req.errors[:base]).to include(I18n.t("citizen_portal.name_change.errors.nothing_changed"))
  end

  it "refuses a date of birth under 18 or in the future" do
    expect(build_request(change_fields: %w[dob], new_dob: 10.years.ago.to_date)).not_to be_valid
    expect(build_request(change_fields: %w[dob], new_dob: 1.day.from_now.to_date)).not_to be_valid
  end

  it "applies the new date of birth and a new BonID when the re-verification is approved" do
    user.generate_bonid!
    old_bonid = user.reload.bonid
    req = build_request(change_fields: %w[dob], new_dob: Date.new(1990, 6, 17))
    req.save!
    req.update_columns(status: NameChangeRequest.statuses[:approved])

    submission = create(:identity_submission, user: user, submission_type: :reissue, reason: "name_change")
    submission.update!(status: :approved, verified_at: Time.current, expires_at: 1.year.from_now)

    expect(user.reload.dob).to eq(Date.new(1990, 6, 17))
    expect(user.bonid).to include("-1990-")
    expect(user.bonid).not_to eq(old_bonid)
    expect(req.reload.applied_at).to be_present
  end
end
