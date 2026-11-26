# frozen_string_literal: true

require "rails_helper"

RSpec.describe InviteCode, "format and lookup" do
  def commune_named(name, prefix: nil)
    c = Commune.first || create(:commune)
    c.name = name
    c.invite_prefix = prefix
    c
  end

  it "generates <PREFIX>-<6 safe chars>" do
    code = InviteCode.create!(code_type: "personal")
    expect(code.code).to match(/\AHTI-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}\z/)
  end

  it "derives the prefix from the commune name" do
    expect(InviteCode.prefix_for(commune_named("Delmas"))).to eq("DEL")
    expect(InviteCode.prefix_for(commune_named("Port-au-Prince"))).to eq("PAP")
    expect(InviteCode.prefix_for(commune_named("Pétion-Ville"))).to eq("PVE")
    expect(InviteCode.prefix_for(nil)).to eq("HTI")
  end

  it "prefers the commune's stored invite_prefix" do
    expect(InviteCode.prefix_for(commune_named("Pétion-Ville", prefix: "pvl"))).to eq("PVL")
  end

  it "finds a code however it was typed" do
    code = InviteCode.create!(code: "DEL-7KQ2XA", code_type: "personal")
    expect(InviteCode.find_available("del 7kq2xa")).to eq(code)
    expect(InviteCode.find_available("del7kq2xa")).to eq(code)
    expect(InviteCode.find_available("DEL-7KQ2XA")).to eq(code)
  end

  it "still finds codes stored in other shapes" do
    code = InviteCode.create!(code: "BONTEST1", code_type: "partner")
    expect(InviteCode.find_available("bontest1")).to eq(code)
  end

  it "ignores exhausted or expired codes" do
    InviteCode.create!(code: "DEL-AAAAAA", code_type: "personal", max_uses: 1, uses_count: 1)
    InviteCode.create!(code: "DEL-BBBBBB", code_type: "personal", expires_at: 1.day.ago)
    expect(InviteCode.find_available("DEL-AAAAAA")).to be_nil
    expect(InviteCode.find_available("DEL-BBBBBB")).to be_nil
  end
end
