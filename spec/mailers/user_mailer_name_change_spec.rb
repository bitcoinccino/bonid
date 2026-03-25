# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  let(:citizen) { create(:user, first_name: "Marie", last_name: "Pierre") }
  let(:admin)   { create(:admin_user) }

  let(:request_record) do
    create(:name_change_request,
           user: citizen,
           new_first_name: "Marie-Anne",
           new_last_name: "Dupont",
           reason: "marriage")
  end

  describe "#name_change_approved" do
    let(:mail) { UserMailer.name_change_approved(citizen, request_record) }

    it "renders the subject" do
      expect(mail.subject).to eq("Your Name Change Has Been Approved")
    end

    it "sends to the citizen's email" do
      expect(mail.to).to eq([citizen.email])
    end

    it "includes the old name in the body" do
      expect(mail.body.encoded).to include(request_record.old_full_name)
    end

    it "includes the new name in the body" do
      expect(mail.body.encoded).to include(request_record.new_full_name)
    end

    it "includes the citizen's first name as greeting" do
      expect(mail.body.encoded).to include(citizen.first_name)
    end
  end

  describe "#name_change_rejected" do
    let(:rejected_request) do
      create(:name_change_request, :rejected,
             user: citizen,
             new_first_name: "Marie-Anne",
             new_last_name: "Dupont",
             reviewed_by: admin)
    end

    let(:mail) { UserMailer.name_change_rejected(citizen, rejected_request) }

    it "renders the subject" do
      expect(mail.subject).to eq("Your Name Change Request Was Not Approved")
    end

    it "sends to the citizen's email" do
      expect(mail.to).to eq([citizen.email])
    end

    it "includes the rejection reason in the body" do
      expect(mail.body.encoded).to include(rejected_request.rejection_reason)
    end

    it "includes the requested new name in the body" do
      expect(mail.body.encoded).to include(rejected_request.new_full_name)
    end
  end
end
