# frozen_string_literal: true

require "rails_helper"

RSpec.describe GovernmentRoleConstants do
  # ── roles_for ────────────────────────────────────────────────
  describe ".roles_for" do
    it "returns ONACA-specific roles (4 roles)" do
      roles = described_class.roles_for("onaca")
      keys = roles.map { |r| r[:key] }
      expect(keys).to eq(%w[partner_admin partner_agent_surveyor partner_agent_notary partner_supervisor])
    end

    it "returns banking-specific roles (4 roles)" do
      roles = described_class.roles_for("banking")
      keys = roles.map { |r| r[:key] }
      expect(keys).to eq(%w[partner_admin bank_agent bank_teller bank_supervisor])
    end

    it "maps all banking sector variants to banking roles" do
      GovernmentRoleConstants::BANKING_SECTORS.each do |sector|
        roles = described_class.roles_for(sector)
        keys = roles.map { |r| r[:key] }
        expect(keys).to include("bank_agent"), "Expected #{sector} to include bank_agent"
      end
    end

    it "returns immigration-specific roles" do
      roles = described_class.roles_for("immigration")
      keys = roles.map { |r| r[:key] }
      expect(keys).to eq(%w[partner_admin partner_agent partner_supervisor])
    end

    it "returns base roles for DGI" do
      roles = described_class.roles_for("dgi")
      keys = roles.map { |r| r[:key] }
      expect(keys).to eq(%w[partner_admin partner_agent partner_supervisor])
    end

    it "returns base roles for unknown sectors" do
      roles = described_class.roles_for("ngo")
      keys = roles.map { |r| r[:key] }
      expect(keys).to eq(%w[partner_admin partner_agent partner_supervisor])
    end
  end

  # ── role_label ───────────────────────────────────────────────
  describe ".role_label" do
    it "returns sector-specific agent label for DGI" do
      expect(described_class.role_label("dgi", "partner_agent")).to eq("Ajan Kesye")
    end

    it "returns Apantè for ONACA surveyor" do
      expect(described_class.role_label("onaca", "partner_agent_surveyor")).to eq("Apantè")
    end

    it "returns Notè for ONACA notary" do
      expect(described_class.role_label("onaca", "partner_agent_notary")).to eq("Notè")
    end

    it "returns Ajan Bank for banking agent" do
      expect(described_class.role_label("banking", "bank_agent")).to eq("Ajan Bank")
    end

    it "returns Kesye for banking teller" do
      expect(described_class.role_label("banking", "bank_teller")).to eq("Kesye")
    end

    it "returns Sipèvizè Bank for banking supervisor" do
      expect(described_class.role_label("banking", "bank_supervisor")).to eq("Sipèvizè Bank")
    end

    it "falls back to titleized key for unknown roles" do
      expect(described_class.role_label("dgi", "unknown_role")).to eq("Unknown Role")
    end
  end

  # ── valid_role_keys_for ──────────────────────────────────────
  describe ".valid_role_keys_for" do
    it "returns 4 keys for ONACA" do
      keys = described_class.valid_role_keys_for("onaca")
      expect(keys.size).to eq(4)
      expect(keys).to include("partner_agent_surveyor", "partner_agent_notary")
    end

    it "returns 4 keys for banking" do
      keys = described_class.valid_role_keys_for("banking")
      expect(keys.size).to eq(4)
      expect(keys).to include("bank_agent", "bank_teller", "bank_supervisor")
    end

    it "returns 3 keys for default sectors" do
      keys = described_class.valid_role_keys_for("healthcare")
      expect(keys.size).to eq(3)
      expect(keys).to eq(%w[partner_admin partner_agent partner_supervisor])
    end

    it "includes partner_admin for all sectors" do
      %w[dgi immigration onaca banking healthcare embassy].each do |sector|
        keys = described_class.valid_role_keys_for(sector)
        expect(keys).to include("partner_admin"), "Expected #{sector} to include partner_admin"
      end
    end
  end

  # ── role_options_for ─────────────────────────────────────────
  describe ".role_options_for" do
    it "returns label-value pairs for form dropdowns" do
      options = described_class.role_options_for("banking")
      expect(options).to be_an(Array)
      expect(options.first).to be_an(Array)
      expect(options.first.size).to eq(2)

      labels = options.map(&:first)
      values = options.map(&:last)
      expect(values).to include("bank_teller")
      expect(labels.find { |l| l.include?("Kesye") }).to be_present
    end
  end
end
