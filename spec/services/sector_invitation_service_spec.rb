
RSpec.describe SectorInvitationService do
  describe ".resolve_user_model_for_sector" do
    it "returns Officer model for law_enforcement sector" do
      model = described_class.resolve_user_model_for_sector("law_enforcement")
      expect(model).to eq(Officer)
    end

    it "returns User model for banking sector" do
      model = described_class.resolve_user_model_for_sector("banking")
      expect(model).to eq(User)
    end

    it "handles alias: hospital → healthcare" do
      model = described_class.resolve_user_model_for_sector("hospital")
      expect(model).to eq(User)
    end

    it "falls back to User for unknown sector" do
      model = described_class.resolve_user_model_for_sector("unknown_sector")
      expect(model).to eq(User)
    end
  end

  describe ".invite_role_for_sector" do
    it "returns 'Officer' role for law_enforcement sector" do
      role = described_class.invite_role_for_sector("law_enforcement")
      expect(role).to eq("Officer")
    end

    it "returns 'Representative' role for banking sector" do
      role = described_class.invite_role_for_sector("banking")
      expect(role).to eq("Representative")
    end

    it "handles alias: hospital → healthcare" do
      role = described_class.invite_role_for_sector("hospital")
      expect(role).to eq("Staff")
    end

    it "falls back to 'Member' for unknown sector" do
      role = described_class.invite_role_for_sector("unknown")
      expect(role).to eq("Member")
    end
  end
end
