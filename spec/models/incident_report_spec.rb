# frozen_string_literal: true

require "rails_helper"

RSpec.describe IncidentReport, type: :model do
  let(:partner) { create(:partner) }

  describe "scopes" do
    describe ".for_unit" do
      let!(:dcpj_officer) { create(:officer, :dcpj, partner: partner) }
      let!(:blts_officer) { create(:officer, :blts, partner: partner) }
      let!(:dcpj_report)  { create(:incident_report, officer: dcpj_officer, partner_id: partner.id) }
      let!(:blts_report)  { create(:incident_report, officer: blts_officer, partner_id: partner.id) }

      it "returns only reports by officers in the specified unit" do
        result = IncidentReport.for_unit("DCPJ", partner.id)
        expect(result).to include(dcpj_report)
        expect(result).not_to include(blts_report)
      end

      it "returns empty for a unit with no reports" do
        expect(IncidentReport.for_unit("EDUPOL", partner.id)).to be_empty
      end
    end

    describe ".joint_task_force" do
      let(:officer) { create(:officer, partner: partner) }
      let!(:kidnapping_report)      { create(:incident_report, :kidnapping, officer: officer, partner_id: partner.id) }
      let!(:child_abduction_report) { create(:incident_report, :child_abduction, officer: officer, partner_id: partner.id) }
      let!(:theft_report)           { create(:incident_report, officer: officer, partner_id: partner.id) }

      it "returns only Kidnapping and Child Abduction reports" do
        result = IncidentReport.joint_task_force
        expect(result).to include(kidnapping_report, child_abduction_report)
        expect(result).not_to include(theft_report)
      end
    end

    describe ".internal_affairs_only" do
      let(:officer) { create(:officer, partner: partner) }
      let!(:brutality_report) { create(:incident_report, :police_brutality, officer: officer, partner_id: partner.id) }
      let!(:theft_report)     { create(:incident_report, officer: officer, partner_id: partner.id) }

      it "returns only Police Brutality reports" do
        result = IncidentReport.internal_affairs_only
        expect(result).to include(brutality_report)
        expect(result).not_to include(theft_report)
      end
    end
  end
end
