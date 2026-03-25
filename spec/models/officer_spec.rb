# frozen_string_literal: true

require "rails_helper"

RSpec.describe Officer, type: :model do
  let(:partner) { create(:partner) }

  describe "scopes" do
    describe ".in_unit" do
      let!(:dcpj_officer) { create(:officer, :dcpj, partner: partner) }
      let!(:blts_officer) { create(:officer, :blts, partner: partner) }
      let!(:swat_officer) { create(:officer, :swat, partner: partner) }

      it "returns only officers in the specified unit" do
        result = Officer.in_unit("DCPJ")
        expect(result).to include(dcpj_officer)
        expect(result).not_to include(blts_officer, swat_officer)
      end

      it "returns empty when no officers in unit" do
        expect(Officer.in_unit("EDUPOL")).to be_empty
      end
    end

    describe ".field_rank" do
      let!(:field)      { create(:officer, :field_rank, partner: partner) }
      let!(:supervisor) { create(:officer, :supervisor_rank, partner: partner) }
      let!(:strategic)  { create(:officer, :strategic_rank, partner: partner) }

      it "returns only field-rank officers" do
        result = Officer.field_rank
        expect(result).to include(field)
        expect(result).not_to include(supervisor, strategic)
      end
    end

    describe ".supervisor_rank" do
      let!(:field)      { create(:officer, :field_rank, partner: partner) }
      let!(:supervisor) { create(:officer, :supervisor_rank, partner: partner) }
      let!(:strategic)  { create(:officer, :strategic_rank, partner: partner) }

      it "returns only supervisor-rank officers" do
        result = Officer.supervisor_rank
        expect(result).to include(supervisor)
        expect(result).not_to include(field, strategic)
      end
    end

    describe ".strategic_rank" do
      let!(:field)      { create(:officer, :field_rank, partner: partner) }
      let!(:supervisor) { create(:officer, :supervisor_rank, partner: partner) }
      let!(:strategic)  { create(:officer, :strategic_rank, partner: partner) }

      it "returns only strategic-rank officers" do
        result = Officer.strategic_rank
        expect(result).to include(strategic)
        expect(result).not_to include(field, supervisor)
      end
    end
  end
end
