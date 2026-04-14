# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerificationRecord, type: :model do
  # ── Associations ─────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:partner).optional }
    it { is_expected.to belong_to(:verifier).optional }
    it { is_expected.to have_one(:address) }
  end

  # ── Validations ──────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:record_type) }
    it { is_expected.to validate_presence_of(:data) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending verified rejected revoked]) }
  end

  # ── Enums ────────────────────────────────────────────────────
  describe "enums" do
    it { is_expected.to define_enum_for(:access_level).with_values(private_access: 0, partners_access: 1, public_access: 2) }
  end

  # Helper to build valid property data (satisfies both flat store_accessor
  # validation and nested PropertySchema concern validation)
  def valid_property_data(overrides = {})
    flat = {
      "title_number" => "TF-12345",
      "property_address" => "123 Rue Capois",
      "commune" => "Port-au-Prince",
      "area_m2" => "150",
      "cadastral_ref" => "PAP-001"
    }
    nested = {
      "property" => {
        "title_number" => "TF-12345",
        "commune" => "Port-au-Prince",
        "area_m2" => "150"
      }
    }
    flat.merge(nested).merge(overrides)
  end

  # ── JSONB Store Accessors ────────────────────────────────────
  describe "JSONB store accessors" do
    let(:user) { create(:user) }
    let(:record) do
      VerificationRecord.create!(
        user: user,
        record_type: "property",
        status: "pending",
        data: valid_property_data
      )
    end

    it "reads property fields from JSONB data via store_accessor" do
      expect(record.title_number).to eq("TF-12345")
      expect(record.cadastral_ref).to eq("PAP-001")
      expect(record.property_address).to eq("123 Rue Capois")
    end

    it "reads area_m2 from store" do
      expect(record.area_m2).to eq("150")
    end
  end

  # ── Property Validation ─────────────────────────────────────
  describe "property validation" do
    let(:user) { create(:user) }

    it "requires title_number, property_address, commune for citizen property records" do
      record = VerificationRecord.new(
        user: user,
        record_type: "property",
        status: "pending",
        data: {}
      )
      expect(record).not_to be_valid
      expect(record.errors[:data].join).to include("title_number")
    end

    it "passes with required property fields" do
      record = VerificationRecord.new(
        user: user,
        record_type: "property",
        status: "pending",
        data: valid_property_data
      )
      expect(record).to be_valid
    end
  end

  # ── Scopes ───────────────────────────────────────────────────
  describe "scopes" do
    let(:user) { create(:user) }
    let(:partner) { create(:partner) }

    before do
      VerificationRecord.create!(user: user, partner: partner, record_type: "property", status: "verified",
        data: valid_property_data("title_number" => "A", "property" => { "title_number" => "A", "commune" => "X", "area_m2" => "10" }))
      VerificationRecord.create!(user: user, record_type: "health", status: "pending",
        data: { "patient_name" => "B" })
      VerificationRecord.create!(user: user, record_type: "property", status: "revoked",
        data: valid_property_data("title_number" => "C", "property" => { "title_number" => "C", "commune" => "Y", "area_m2" => "20" }))
    end

    it ".active excludes revoked records" do
      expect(VerificationRecord.active.count).to eq(2)
    end

    it ".for_type filters by record type" do
      expect(VerificationRecord.for_type("property").count).to eq(2)
      expect(VerificationRecord.for_type("health").count).to eq(1)
    end

    it ".by_partner filters by partner" do
      expect(VerificationRecord.by_partner(partner).count).to eq(1)
    end
  end

  # ── Business Record ─────────────────────────────────────────
  describe "business records" do
    let(:user) { create(:user) }

    it "stores business data in JSONB" do
      record = VerificationRecord.create!(
        user: user,
        record_type: "business",
        status: "pending",
        data: {
          "business_name" => "Ti Machann SARL",
          "registration_number" => "REG-2026-001",
          "business_type" => "commerce",
          "legal_structure" => "SARL",
          "nif" => "NIF-HT-123456789",
          "business_address" => "Rue du Commerce 5, Port-au-Prince",
          "sector" => "commerce",
          "cnss_employer_number" => "CNSS-BIZ-2026-001",
          "incorporation_date" => "2026-01-01",
          "owner_role" => "gérant",
          "employees_count" => "5"
        }
      )
      expect(record.business_name).to eq("Ti Machann SARL")
      expect(record.sector).to eq("commerce")
    end
  end
end
