class AddEmailOtpToVisitorSubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :visitor_submissions, :email_otp, :string
    add_column :visitor_submissions, :email_otp_sent_at, :datetime
    add_column :visitor_submissions, :email_verified_at, :datetime

    add_index :visitor_submissions, :email_otp
  end
end
