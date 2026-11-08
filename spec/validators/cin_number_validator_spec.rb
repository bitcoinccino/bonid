# frozen_string_literal: true

require "rails_helper"

RSpec.describe CinNumberValidator do
  describe ".valid? for CIN" do
    it "accepts the number printed on the CIN card" do
      expect(described_class.valid?("T1K2N8697", :cin)).to be(true)
      expect(described_class.valid?("t1k2n8697", :cin)).to be(true)
    end

    it "accepts a 10-digit NINU, with or without separators" do
      expect(described_class.valid?("0123456789", :cin)).to be(true)
      expect(described_class.valid?("012-345-6789", :cin)).to be(true)
    end

    it "rejects other lengths and characters" do
      expect(described_class.valid?("T1K2N869", :cin)).to be(false)
      expect(described_class.valid?("12345678901234", :cin)).to be(false)
      expect(described_class.valid?("T1K2N8697!", :cin)).to be(false)
      expect(described_class.valid?("", :cin)).to be(false)
    end
  end

  describe ".generation" do
    it "tells NINU from the CIN card number" do
      expect(described_class.generation("0123456789")).to eq(:ninu)
      expect(described_class.generation("T1K2N8697")).to eq(:cin_card)
      expect(described_class.generation("bad")).to be_nil
    end
  end

  it "lets a citizen save their CIN card number on the profile" do
    user = create(:user, :with_address)
    user.assign_attributes(id_type: :cin, id_number: "T1K2N8697")
    expect(user).to be_valid
  end
end
