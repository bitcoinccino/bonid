# frozen_string_literal: true

class ChangeSubmissionTypeToIntegerInIdentitySubmissions < ActiveRecord::Migration[7.1]
  def up
    # 1️⃣ Add new integer column temporarily
    add_column :identity_submissions, :submission_type_tmp, :integer, default: 0

    # 2️⃣ Copy data from old string column → new integer column
    say_with_time "Migrating submission_type values..." do
      IdentitySubmission.reset_column_information
      IdentitySubmission.find_each do |submission|
        case submission.read_attribute(:submission_type).to_s
        when "initial"       then submission.update_column(:submission_type_tmp, 0)
        when "resubmission"  then submission.update_column(:submission_type_tmp, 1)
        when "reissue"       then submission.update_column(:submission_type_tmp, 2)
        end
      end
    end

    # 3️⃣ Replace old column
    remove_column :identity_submissions, :submission_type
    rename_column :identity_submissions, :submission_type_tmp, :submission_type
  end

  def down
    # 4️⃣ Reverse migration if rolled back
    add_column :identity_submissions, :submission_type_tmp, :string

    say_with_time "Reverting submission_type to string..." do
      IdentitySubmission.reset_column_information
      IdentitySubmission.find_each do |submission|
        case submission.submission_type
        when 0 then submission.update_column(:submission_type_tmp, "initial")
        when 1 then submission.update_column(:submission_type_tmp, "resubmission")
        when 2 then submission.update_column(:submission_type_tmp, "reissue")
        end
      end
    end

    remove_column :identity_submissions, :submission_type
    rename_column :identity_submissions, :submission_type_tmp, :submission_type
  end
end
