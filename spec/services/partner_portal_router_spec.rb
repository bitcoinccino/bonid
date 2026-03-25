# spec/services/partner_portal_router_spec.rb
require "rails_helper"

RSpec.describe PartnerPortalRouter, type: :service do
  let(:partner) { double("Partner", sector: sector) }
  let(:admin)   { double("PartnerAdmin", partner: partner) }

  describe ".dashboard_path_for" do
    context "when partner is missing" do
      it "returns fallback path" do
        expect(described_class.dashboard_path_for(nil)).to eq("/partner_portal")
      end
    end

    context "when sector is banking" do
      let(:sector) { "banking" }
      it "returns banking dashboard path" do
        expect(described_class.dashboard_path_for(admin)).to eq("/partner_portal/banking/dashboard")
      end
    end

    context "when sector is embassy_services" do
      let(:sector) { "embassy_services" }
      it "returns embassy dashboard path" do
        expect(described_class.dashboard_path_for(admin)).to eq("/partner_portal/embassy/dashboard")
      end
    end

    context "when sector is hospital" do
      let(:sector) { "hospital" }
      it "returns hospital dashboard path" do
        expect(described_class.dashboard_path_for(admin)).to eq("/partner_portal/hospital/dashboard")
      end
    end

    context "when sector is law_enforcement" do
      let(:sector) { "law_enforcement" }
      it "returns law enforcement dashboard path" do
        expect(described_class.dashboard_path_for(admin)).to eq("/partner_portal/law_enforcement/dashboard")
      end
    end

    context "when unknown sector" do
      let(:sector) { "unknown" }
      it "returns generic dashboard path" do
        expect(described_class.dashboard_path_for(admin)).to eq("/partner_portal/dashboard")
      end
    end
  end

  describe ".onboarding_path_for" do
    let(:sector) { "banking" }

    it "redirects to new partner_applications if no partner" do
      expect(described_class.onboarding_path_for(nil)).to eq("/partner_applications/new")
    end

    it "redirects to pending review if partner is pending" do
      pending_partner = double("Partner", sector: "banking", pending?: true)
      admin = double("PartnerAdmin", partner: pending_partner)
      expect(described_class.onboarding_path_for(admin)).to eq("/partner_portal/pending_review")
    end

    it "redirects to dashboard for verified partners" do
      verified_partner = double("Partner", sector: "embassy", pending?: false)
      admin = double("PartnerAdmin", partner: verified_partner)
      expect(described_class.onboarding_path_for(admin)).to eq("/partner_portal/embassy/dashboard")
    end
  end

  describe ".sector_label_for" do
    it "returns human-readable label for known sector" do
      partner = double("Partner", sector: "banking")
      expect(described_class.sector_label_for(partner)).to eq("Banking")
    end

    it "returns 'Partner' for unknown sector" do
      partner = double("Partner", sector: "unknown")
      expect(described_class.sector_label_for(partner)).to eq("Partner")
    end
  end
end
