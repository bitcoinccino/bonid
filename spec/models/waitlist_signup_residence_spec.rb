# frozen_string_literal: true

require "rails_helper"

RSpec.describe WaitlistSignup, "US state and city" do
  def build(attrs)
    described_class.new({ email: "rose@example.com", signup_type: "citizen" }.merge(attrs))
  end

  it "keeps state and city for a US diaspora signup" do
    s = build(diaspora: true, country_of_residence: "US", residence_state: "fl", residence_city: "  North  Miami ")
    expect(s).to be_valid
    expect([s.residence_state, s.residence_city]).to eq(["FL", "North Miami"])
    expect(s.residence_place).to eq("North Miami, Florida")
  end

  it "drops state and city outside the US" do
    s = build(diaspora: true, country_of_residence: "CA", residence_state: "FL", residence_city: "Miami")
    s.valid?
    expect([s.residence_state, s.residence_city]).to eq([nil, nil])
  end

  it "drops them for signups in Haiti" do
    s = build(diaspora: false, country_of_residence: "US", residence_state: "FL", residence_city: "Miami")
    s.valid?
    expect(s.residence_state).to be_nil
  end

  it "rejects an unknown state" do
    expect(build(diaspora: true, country_of_residence: "US", residence_state: "ZZ")).not_to be_valid
  end

  it "keeps a typed city that is not in the suggestions" do
    s = build(diaspora: true, country_of_residence: "US", residence_state: "TX", residence_city: "Sugar Land")
    expect(s).to be_valid
    expect(s.residence_place).to eq("Sugar Land, Texas")
  end

  describe "city suggestions" do
    it "puts the curated cities first, then every Census place without duplicates" do
      fl = DiasporaLocations.cities_for("fl")
      expect(fl.first(3)).to eq(["Miami", "North Miami", "North Miami Beach"])
      expect(fl).to include("Miami Gardens", "Hialeah")
      expect(fl.uniq.size).to eq(fl.size)
    end

    it "covers states without a curated list" do
      expect(DiasporaLocations.cities_for("TX")).to include("Houston", "Dallas")
    end

    it "strips Census suffixes (city, town, CDP, balance...)" do
      all = DiasporaLocations.census_cities.values.flatten
      expect(all.grep(/ (CDP|city|town|village|borough|government|county|township|\(balance\))\z/)).to be_empty
      expect(DiasporaLocations.cities_for("TN")).to include("Nashville-Davidson")
      expect(DiasporaLocations.cities_for("AL")).to include("Phenix City")
    end

    it "is empty for an unknown state" do
      expect(DiasporaLocations.cities_for("ZZ")).to eq([])
    end
  end

  it "groups the priority states first, then the rest A to Z" do
    groups = DiasporaLocations.state_groups
    expect(groups[:priority].map(&:last)).to eq(%w[FL NY MA NJ GA IL PA MD])
    expect(groups[:other].map(&:first)).to eq(groups[:other].map(&:first).sort)
    expect(groups[:priority].size + groups[:other].size).to eq(51)
  end

  it "accepts only the countries open for signup for citizens abroad" do
    expect(build(diaspora: true, country_of_residence: "CA")).not_to be_valid
    expect(build(diaspora: true, country_of_residence: "US", residence_state: "FL")).to be_valid
    expect(build(diaspora: true, country_of_residence: "CA", signup_type: "business",
                 organization_name: "Org", sector: "banking")).to be_valid
  end
end
