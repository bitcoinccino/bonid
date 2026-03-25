# frozen_string_literal: true

require "rails_helper"

RSpec.describe OfficerAccessControl, type: :model do
  # All tests use the Officer model which includes OfficerAccessControl

  let(:partner) { create(:partner) }

  # ================================================================
  # A. RANK GROUP PREDICATES
  # ================================================================
  describe "#rank_group" do
    context "with field ranks" do
      %w[Agent\ I Agent\ II Agent\ III Agent\ Principal].each do |rank_name|
        it "returns :field for #{rank_name}" do
          officer = build(:officer, rank: rank_name, partner: partner)
          expect(officer.rank_group).to eq(:field)
        end
      end
    end

    context "with supervisor ranks" do
      ["Inspecteur de Police", "Inspecteur Principal", "Inspecteur Divisionnaire", "Sous-Commissaire"].each do |rank_name|
        it "returns :supervisor for #{rank_name}" do
          officer = build(:officer, rank: rank_name, partner: partner)
          expect(officer.rank_group).to eq(:supervisor)
        end
      end
    end

    context "with strategic ranks" do
      ["Commissaire de Police", "Commissaire Principal", "Commissaire Divisionnaire", "Inspecteur Général", "Directeur Général"].each do |rank_name|
        it "returns :strategic for #{rank_name}" do
          officer = build(:officer, rank: rank_name, partner: partner)
          expect(officer.rank_group).to eq(:strategic)
        end
      end
    end

    context "with unknown or blank rank" do
      it "defaults to :field for unknown rank" do
        officer = build(:officer, rank: "Unknown Rank", partner: partner)
        expect(officer.rank_group).to eq(:field)
      end

      it "defaults to :field for nil rank" do
        officer = build(:officer, partner: partner)
        officer.rank = nil
        expect(officer.rank_group).to eq(:field)
      end

      it "defaults to :field for blank rank" do
        officer = build(:officer, partner: partner)
        officer.rank = ""
        expect(officer.rank_group).to eq(:field)
      end
    end
  end

  describe "#field_rank?" do
    it "returns true for field rank officers" do
      officer = build(:officer, :field_rank, partner: partner)
      expect(officer.field_rank?).to be true
    end

    it "returns false for supervisor rank officers" do
      officer = build(:officer, :supervisor_rank, partner: partner)
      expect(officer.field_rank?).to be false
    end
  end

  describe "#supervisor_rank?" do
    it "returns true for supervisor rank officers" do
      officer = build(:officer, :supervisor_rank, partner: partner)
      expect(officer.supervisor_rank?).to be true
    end

    it "returns false for field rank officers" do
      officer = build(:officer, :field_rank, partner: partner)
      expect(officer.supervisor_rank?).to be false
    end
  end

  describe "#strategic_rank?" do
    it "returns true for strategic rank officers" do
      officer = build(:officer, :strategic_rank, partner: partner)
      expect(officer.strategic_rank?).to be true
    end

    it "returns false for field rank officers" do
      officer = build(:officer, :field_rank, partner: partner)
      expect(officer.strategic_rank?).to be false
    end
  end

  # ================================================================
  # B. UNIT ACCESS PREDICATES
  # ================================================================
  describe "#restricted_unit?" do
    it "returns true for USGPN" do
      officer = build(:officer, :usgpn, partner: partner)
      expect(officer.restricted_unit?).to be true
    end

    it "returns true for USP" do
      officer = build(:officer, :usp, partner: partner)
      expect(officer.restricted_unit?).to be true
    end

    it "returns false for DCPJ" do
      officer = build(:officer, :dcpj, partner: partner)
      expect(officer.restricted_unit?).to be false
    end

    it "returns false for EDUPOL" do
      officer = build(:officer, :edupol, partner: partner)
      expect(officer.restricted_unit?).to be false
    end
  end

  describe "#bonid_access_level" do
    context "full access units" do
      %w[DCPJ POLIFRONT BLTS BRI UTAG SWAT USGPN USP].each do |unit|
        it "returns 'full' for #{unit}" do
          officer = build(:officer, unit_name: unit, unit_type: OfficerConstants::UNIT_OPTIONS[unit]&.first, partner: partner)
          expect(officer.bonid_access_level).to eq("full")
        end
      end
    end

    context "limited access units" do
      %w[EDUPOL POLITOUR DCPR].each do |unit|
        it "returns 'limited' for #{unit}" do
          officer = build(:officer, unit_name: unit, unit_type: OfficerConstants::UNIT_OPTIONS[unit]&.first, partner: partner)
          expect(officer.bonid_access_level).to eq("limited")
        end
      end
    end

    context "standard access units" do
      %w[CIMO UDMO BOID POLAER BIM].each do |unit|
        it "returns 'standard' for #{unit}" do
          officer = build(:officer, unit_name: unit, unit_type: OfficerConstants::UNIT_OPTIONS[unit]&.first, partner: partner)
          expect(officer.bonid_access_level).to eq("standard")
        end
      end
    end

    it "defaults to 'standard' for unknown unit" do
      officer = build(:officer, partner: partner)
      officer.unit_name = "UNKNOWN"
      expect(officer.bonid_access_level).to eq("standard")
    end
  end

  describe "#full_bonid_access?" do
    it "returns true for DCPJ officer" do
      officer = build(:officer, :dcpj, partner: partner)
      expect(officer.full_bonid_access?).to be true
    end

    it "returns false for EDUPOL officer" do
      officer = build(:officer, :edupol, partner: partner)
      expect(officer.full_bonid_access?).to be false
    end
  end

  describe "#limited_bonid_access?" do
    it "returns true for EDUPOL officer" do
      officer = build(:officer, :edupol, partner: partner)
      expect(officer.limited_bonid_access?).to be true
    end

    it "returns false for DCPJ officer" do
      officer = build(:officer, :dcpj, partner: partner)
      expect(officer.limited_bonid_access?).to be false
    end
  end

  describe "#standard_bonid_access?" do
    it "returns true for CIMO officer" do
      officer = build(:officer, :cimo, partner: partner)
      expect(officer.standard_bonid_access?).to be true
    end

    it "returns false for DCPJ officer" do
      officer = build(:officer, :dcpj, partner: partner)
      expect(officer.standard_bonid_access?).to be false
    end
  end

  describe "#authorized_crime_categories" do
    it "returns correct categories for DCPJ" do
      officer = build(:officer, :dcpj, partner: partner)
      expect(officer.authorized_crime_categories).to eq(%w[violent_crimes economic_crimes organized_crime])
    end

    it "returns correct categories for EDUPOL" do
      officer = build(:officer, :edupol, partner: partner)
      expect(officer.authorized_crime_categories).to eq(%w[social_and_emerging_crimes traffic_and_minor_infractions])
    end

    it "returns correct categories for BLTS" do
      officer = build(:officer, :blts, partner: partner)
      expect(officer.authorized_crime_categories).to eq(%w[organized_crime smuggling_and_trafficking])
    end

    it "returns empty array for unknown unit" do
      officer = build(:officer, partner: partner)
      officer.unit_name = "UNKNOWN"
      expect(officer.authorized_crime_categories).to eq([])
    end
  end

  describe "#crime_type_authorized?" do
    context "for field rank officers" do
      let(:dcpj_field) { build(:officer, :field_rank, :dcpj, partner: partner) }

      it "returns true for a crime type in the unit's authorized list" do
        # DCPJ has violent_crimes which includes "Kidnapping"
        expect(dcpj_field.crime_type_authorized?("Kidnapping")).to be true
      end

      it "returns false for a crime type NOT in the unit's authorized list" do
        # "Traffic Violation" is in traffic_and_minor_infractions, not in DCPJ's categories
        expect(dcpj_field.crime_type_authorized?("Traffic Violation")).to be false
      end
    end

    context "for supervisor rank officers" do
      it "always returns true regardless of crime type" do
        officer = build(:officer, :supervisor_rank, :edupol, partner: partner)
        expect(officer.crime_type_authorized?("Kidnapping")).to be true
      end
    end

    context "for strategic rank officers" do
      it "always returns true regardless of crime type" do
        officer = build(:officer, :strategic_rank, :edupol, partner: partner)
        expect(officer.crime_type_authorized?("Treason")).to be true
      end
    end

    context "for unknown unit (empty categories)" do
      it "returns true as fallback when no mapping defined" do
        officer = build(:officer, :field_rank, partner: partner)
        officer.unit_name = "UNKNOWN"
        expect(officer.crime_type_authorized?("Anything")).to be true
      end
    end
  end

  # ================================================================
  # C. INCIDENT REPORT VISIBILITY (requires DB records)
  # ================================================================
  describe "#visible_incident_reports" do
    let!(:dcpj_field_officer) { create(:officer, :field_rank, :dcpj, partner: partner) }
    let!(:dcpj_colleague)     { create(:officer, :field_rank, :dcpj, partner: partner) }
    let!(:blts_officer)       { create(:officer, :field_rank, :blts, partner: partner) }

    let!(:own_report)       { create(:incident_report, officer: dcpj_field_officer, partner_id: partner.id) }
    let!(:colleague_report) { create(:incident_report, officer: dcpj_colleague, partner_id: partner.id) }
    let!(:blts_report)      { create(:incident_report, officer: blts_officer, partner_id: partner.id) }

    context "field rank officer" do
      it "sees only their own reports" do
        reports = dcpj_field_officer.visible_incident_reports
        expect(reports).to include(own_report)
        expect(reports).not_to include(colleague_report)
        expect(reports).not_to include(blts_report)
      end
    end

    context "supervisor rank officer" do
      it "sees all reports from officers in the same unit" do
        supervisor = create(:officer, :supervisor_rank, :dcpj, partner: partner)
        reports = supervisor.visible_incident_reports
        expect(reports).to include(own_report, colleague_report)
        expect(reports).not_to include(blts_report)
      end
    end

    context "strategic rank officer" do
      it "sees ALL partner reports across all units" do
        strategic = create(:officer, :strategic_rank, :dcpj, partner: partner)
        reports = strategic.visible_incident_reports
        expect(reports).to include(own_report, colleague_report, blts_report)
      end
    end
  end

  describe "#joint_task_force_crime_types" do
    it "returns JTF trigger list for DCPJ officer" do
      officer = build(:officer, :dcpj, partner: partner)
      expect(officer.joint_task_force_crime_types).to eq(["Kidnapping", "Child Abduction"])
    end

    it "returns JTF trigger list for SWAT officer" do
      officer = build(:officer, :swat, partner: partner)
      expect(officer.joint_task_force_crime_types).to eq(["Kidnapping", "Child Abduction"])
    end

    it "returns empty array for EDUPOL officer" do
      officer = build(:officer, :edupol, partner: partner)
      expect(officer.joint_task_force_crime_types).to eq([])
    end

    it "returns empty array for BLTS officer" do
      officer = build(:officer, :blts, partner: partner)
      expect(officer.joint_task_force_crime_types).to eq([])
    end
  end

  describe "#joint_task_force_reports" do
    let!(:dcpj_officer) { create(:officer, :field_rank, :dcpj, partner: partner) }
    let!(:blts_officer) { create(:officer, :field_rank, :blts, partner: partner) }
    let!(:edupol_officer) { create(:officer, :field_rank, :edupol, partner: partner) }

    let!(:kidnapping_report) { create(:incident_report, :kidnapping, officer: blts_officer, partner_id: partner.id) }
    let!(:theft_report)      { create(:incident_report, officer: blts_officer, partner_id: partner.id) }

    it "returns JTF-matching reports for DCPJ officer" do
      reports = dcpj_officer.joint_task_force_reports
      expect(reports).to include(kidnapping_report)
      expect(reports).not_to include(theft_report)
    end

    it "returns none for non-JTF unit officer" do
      reports = edupol_officer.joint_task_force_reports
      expect(reports).to be_empty
    end
  end

  describe "#effective_incident_reports" do
    let!(:dcpj_field)    { create(:officer, :field_rank, :dcpj, partner: partner) }
    let!(:blts_officer)  { create(:officer, :field_rank, :blts, partner: partner) }

    let!(:own_report)        { create(:incident_report, officer: dcpj_field, partner_id: partner.id) }
    let!(:kidnapping_by_blts) { create(:incident_report, :kidnapping, officer: blts_officer, partner_id: partner.id) }
    let!(:theft_by_blts)     { create(:incident_report, officer: blts_officer, partner_id: partner.id) }

    it "merges own reports + JTF cross-unit reports for DCPJ field officer" do
      reports = dcpj_field.effective_incident_reports
      expect(reports).to include(own_report)
      expect(reports).to include(kidnapping_by_blts)  # JTF override
      expect(reports).not_to include(theft_by_blts)   # no access to other unit's non-JTF
    end

    it "for strategic officer, returns all partner reports" do
      strategic = create(:officer, :strategic_rank, :dcpj, partner: partner)
      reports = strategic.effective_incident_reports
      expect(reports).to include(own_report, kidnapping_by_blts, theft_by_blts)
    end
  end

  # ================================================================
  # D. ANALYTICS SCOPE
  # ================================================================
  describe "#max_analytics_scope" do
    it "returns 'personal' for field rank" do
      officer = build(:officer, :field_rank, partner: partner)
      expect(officer.max_analytics_scope).to eq("personal")
    end

    it "returns 'station' for supervisor rank" do
      officer = build(:officer, :supervisor_rank, partner: partner)
      expect(officer.max_analytics_scope).to eq("station")
    end

    it "returns 'department' for strategic rank" do
      officer = build(:officer, :strategic_rank, partner: partner)
      expect(officer.max_analytics_scope).to eq("department")
    end
  end

  describe "#analytics_scope_allowed?" do
    let(:field_officer)      { build(:officer, :field_rank, partner: partner) }
    let(:supervisor_officer) { build(:officer, :supervisor_rank, partner: partner) }
    let(:strategic_officer)  { build(:officer, :strategic_rank, partner: partner) }

    context "field rank" do
      it "allows 'personal'" do
        expect(field_officer.analytics_scope_allowed?("personal")).to be true
      end

      it "denies 'station'" do
        expect(field_officer.analytics_scope_allowed?("station")).to be false
      end

      it "denies 'department'" do
        expect(field_officer.analytics_scope_allowed?("department")).to be false
      end
    end

    context "supervisor rank" do
      it "allows 'personal'" do
        expect(supervisor_officer.analytics_scope_allowed?("personal")).to be true
      end

      it "allows 'station'" do
        expect(supervisor_officer.analytics_scope_allowed?("station")).to be true
      end

      it "denies 'department'" do
        expect(supervisor_officer.analytics_scope_allowed?("department")).to be false
      end
    end

    context "strategic rank" do
      it "allows 'personal'" do
        expect(strategic_officer.analytics_scope_allowed?("personal")).to be true
      end

      it "allows 'station'" do
        expect(strategic_officer.analytics_scope_allowed?("station")).to be true
      end

      it "allows 'department'" do
        expect(strategic_officer.analytics_scope_allowed?("department")).to be true
      end

      it "denies 'national' (Phase 2)" do
        expect(strategic_officer.analytics_scope_allowed?("national")).to be false
      end
    end
  end

  # ================================================================
  # E. CLASS METHODS — PORTAL ADMIN SCOPE
  # ================================================================
  describe ".officer_for_admin" do
    it "finds the linked officer by email and partner_id" do
      officer = create(:officer, partner: partner)
      admin = double("PartnerAdmin", email: officer.email, partner: partner)

      found = Officer.officer_for_admin(admin)
      expect(found).to eq(officer)
    end

    it "returns nil when no matching officer exists" do
      admin = double("PartnerAdmin", email: "noone@example.com", partner: partner)

      found = Officer.officer_for_admin(admin)
      expect(found).to be_nil
    end

    it "returns nil when admin has no partner" do
      admin = double("PartnerAdmin", email: "test@example.com", partner: nil)

      found = Officer.officer_for_admin(admin)
      expect(found).to be_nil
    end
  end

  describe ".portal_admin_scope_for" do
    it "returns :full when no linked officer exists" do
      admin = double("PartnerAdmin", email: "noone@example.com", partner: partner)

      scope = Officer.portal_admin_scope_for(admin)
      expect(scope).to eq(:full)
    end

    it "returns :full for strategic-rank linked officer" do
      officer = create(:officer, :strategic_rank, partner: partner)
      admin = double("PartnerAdmin", email: officer.email, partner: partner)

      scope = Officer.portal_admin_scope_for(admin)
      expect(scope).to eq(:full)
    end

    it "returns :unit for field-rank linked officer" do
      officer = create(:officer, :field_rank, partner: partner)
      admin = double("PartnerAdmin", email: officer.email, partner: partner)

      scope = Officer.portal_admin_scope_for(admin)
      expect(scope).to eq(:unit)
    end

    it "returns :unit for supervisor-rank linked officer" do
      officer = create(:officer, :supervisor_rank, partner: partner)
      admin = double("PartnerAdmin", email: officer.email, partner: partner)

      scope = Officer.portal_admin_scope_for(admin)
      expect(scope).to eq(:unit)
    end
  end
end
