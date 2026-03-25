# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoleRedirectService, type: :service do
  describe ".redirect_path_for" do
    let(:admin_user) { build_stubbed(:admin_user) }
    let(:officer) { build_stubbed(:officer) }
    let(:citizen) { build_stubbed(:user, roles: [ build_stubbed(:role, name: "citizen") ]) }
    let(:partner_admin) { build_stubbed(:user, roles: [ build_stubbed(:role, name: "partner_admin") ]) }
    let(:reviewer) { build_stubbed(:user, roles: [ build_stubbed(:role, name: "reviewer") ]) }

    it "redirects admin users to /admin" do
      expect(described_class.redirect_path_for(admin_user)).to eq("/admin")
    end

    it "redirects officers to /officers/dashboard" do
      expect(described_class.redirect_path_for(officer)).to eq("/officers/dashboard")
    end

    it "redirects partner admins to /partner_portal/dashboard" do
      expect(described_class.redirect_path_for(partner_admin)).to eq("/partner_portal/dashboard")
    end

    it "redirects citizens to /citizens/verification_records" do
      expect(described_class.redirect_path_for(citizen)).to eq("/citizens/verification_records")
    end

    it "redirects reviewers to /admin/identity_submissions" do
      expect(described_class.redirect_path_for(reviewer)).to eq("/admin/identity_submissions")
    end

    it "returns root for nil or unknown types" do
      expect(described_class.redirect_path_for(nil)).to eq("/")
      expect(described_class.redirect_path_for(Object.new)).to eq("/")
    end
  end
end
