# spec/services/partner_portal_router_spec.rb
require "rails_helper"

RSpec.describe PartnerPortalRouter, type: :service do
  let(:partner) { double("Partner", sector: sector) }
  let(:admin)   { double("PartnerAdmin", partner: partner) }

  describe ".dashboard_path_for" do
    context "when the resource is missing" do
      it "returns the portal root" do
        expect(described_class.dashboard_path_for(nil)).to eq("/partner_portal")
      end
    end

    context "when the resource has no partner" do
      let(:admin) { double("PartnerAdmin", partner: nil) }

      it "returns the portal root" do
        expect(described_class.dashboard_path_for(admin)).to eq("/partner_portal")
      end
    end

    context "when sector is law_enforcement" do
      let(:sector) { "law_enforcement" }

      it "returns the law enforcement dashboard" do
        expect(described_class.dashboard_path_for(admin)).to eq("/partner_portal/law_enforcement/dashboard")
      end
    end

    %w[banking embassy hospital unknown].each do |s|
      context "when sector is #{s}" do
        let(:sector) { s }

        it "returns the shared portal root" do
          expect(described_class.dashboard_path_for(admin)).to eq("/partner_portal")
        end
      end
    end
  end
end
