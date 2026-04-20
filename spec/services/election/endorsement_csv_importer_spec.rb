# frozen_string_literal: true

require "rails_helper"
require "stringio"

RSpec.describe Election::EndorsementCsvImporter do
  let(:election)     { create(:bonvote_election) }
  let(:constituency) { create(:election_constituency, election: election) }
  let(:candidate) do
    create(:election_candidate,
           election: election, election_constituency: constituency,
           candidacy_type: "independent")
  end
  let(:admin) { create(:admin_user) }

  def import(csv_text)
    described_class.new(candidate: candidate, csv_io: StringIO.new(csv_text), admin: admin).call
  end

  it "imports rows with a CIN and stamps them as source=csv" do
    result = import("cin_number,full_name\nCIN-100,Jean Dupont\nCIN-101,Marie Duval\n")
    expect(result.imported).to eq(2)
    expect(ElectionCandidateEndorsement.where(election_candidate: candidate, source: "csv").count).to eq(2)
  end

  it "matches CIN against VoterEligibilityRecord and stamps bonid + verified=true" do
    voter = create(:voter_eligibility_record,
                   bonvote_election: election, cin_number: "MATCHED-CIN", bonid: "BONID-FROM-ROLL")
    result = import("cin_number\nMATCHED-CIN\n")
    expect(result.verified).to eq(1)
    row = ElectionCandidateEndorsement.find_by(cin_number: "MATCHED-CIN")
    expect(row.bonid).to eq(voter.bonid)
    expect(row.voter_roll_verified).to be true
  end

  it "leaves unmatched rows unverified but still imported" do
    result = import("cin_number\nUNMATCHED-CIN\n")
    expect(result.imported).to eq(1)
    expect(result.unverified).to eq(1)
    expect(ElectionCandidateEndorsement.find_by(cin_number: "UNMATCHED-CIN").voter_roll_verified).to be false
  end

  it "collapses duplicate CINs within the same file" do
    result = import("cin_number\nCIN-SAME\nCIN-SAME\nCIN-OTHER\n")
    expect(result.imported).to eq(2)
    expect(result.duplicates).to eq(1)
  end

  it "skips CINs already endorsing (via bonid match) from a previous import" do
    create(:voter_eligibility_record, bonvote_election: election, cin_number: "REPEAT", bonid: "REPEAT-BONID")
    import("cin_number\nREPEAT\n")
    result = import("cin_number\nREPEAT\n")
    expect(result.imported).to eq(0)
    expect(result.duplicates).to eq(1)
  end

  it "skips CINs already endorsing via an unmatched prior row" do
    import("cin_number\nORPHAN-CIN\n")
    result = import("cin_number\nORPHAN-CIN\n")
    expect(result.imported).to eq(0)
    expect(result.duplicates).to eq(1)
  end

  it "ignores blank cin_number rows" do
    result = import("cin_number,full_name\n,Empty Row\nCIN-OK,Real Person\n")
    expect(result.imported).to eq(1)
  end

  it "records uploader admin on each row" do
    import("cin_number\nCIN-200\n")
    expect(ElectionCandidateEndorsement.find_by(cin_number: "CIN-200").uploaded_by).to eq(admin)
  end

  it "captures signature_image_url and notes when present" do
    import("cin_number,full_name,signature_image_url,notes\nCIN-300,Jean Paul,https://example.com/sig.png,Papye peyi\n")
    row = ElectionCandidateEndorsement.find_by(cin_number: "CIN-300")
    expect(row.signature_image_url).to eq("https://example.com/sig.png")
    expect(row.notes).to include("Jean Paul").and include("Papye peyi")
  end
end
