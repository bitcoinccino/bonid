require 'rails_helper'

RSpec.describe User, type: :model do
  describe "Factory setup" do
    it "creates a verified user" do
      user = create(:user, :verified)
      expect(user.identity_submissions.first.status).to eq("approved")
      expect(user.bonid).to eq(user.identity_submissions.first.bonid)
    end

    it "creates a user with an address" do
      user = create(:user, :with_address)
      expect(user.address).not_to be_nil
      expect(user.address.locality).to eq("Port-au-Prince")
    end
  end
end
