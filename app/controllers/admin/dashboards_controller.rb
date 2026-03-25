class Admin::DashboardsController < Admin::ApplicationController
  before_action :authenticate_admin_user!
  require "csv"

  # ============================================================
  # MAIN DASHBOARD
  # ============================================================
  def index
    # =======================================
    # BASIC OVERVIEW STATS (cached, fast)
    # =======================================
    @partners_count              = Rails.cache.fetch("admin/dash/partners",        expires_in: 5.minutes) { Partner.count }
    @active_partners_count       = Rails.cache.fetch("admin/dash/active_partners", expires_in: 5.minutes) { Partner.where.not(status: :rejected).count }
    @rejected_applications_count = Rails.cache.fetch("admin/dash/rejected",        expires_in: 5.minutes) { Partner.where(status: :rejected).count }
    @officers_count              = Rails.cache.fetch("admin/dash/officers",         expires_in: 5.minutes) { Officer.count }
    @pending_submissions_count   = Rails.cache.fetch("admin/dash/pending",         expires_in: 2.minutes) { IdentitySubmission.where(status: "pending").count }
    @verified_submissions_count  = Rails.cache.fetch("admin/dash/verified",        expires_in: 2.minutes) { IdentitySubmission.where(status: "approved").count }

    # =======================================
    # RECENT ACTIVITY (fast, limit 5)
    # =======================================
    @recent_partners    = Partner.order(created_at: :desc).limit(5)
    @recent_submissions = IdentitySubmission.order(created_at: :desc).limit(5)
  end

  # ============================================================
  # LAZY-LOADED CHARTS (via Turbo Frame)
  # ============================================================
  def charts
    # =======================================
    # TIME-BASED VERIFICATION ANALYTICS
    # =======================================
    @submissions_daily   = IdentitySubmission.group_by_day(:created_at,   last: 14).count || {}
    @submissions_weekly  = IdentitySubmission.group_by_week(:created_at,  last: 12).count || {}
    @submissions_monthly = IdentitySubmission.group_by_month(:created_at, last: 12).count || {}
    @submissions_yearly  = IdentitySubmission.group_by_year(:created_at,  last: 5).count || {}

    # =======================================
    # USER DEMOGRAPHICS
    # =======================================
    @gender_breakdown = User.group(:sex).count || {}

    @under_18 = User.where("dob > ?", 18.years.ago).count
    @over_65  = User.where("dob < ?", 65.years.ago).count

    @age_groups = {
      "Under 18" => @under_18,
      "18–65"    => User.where(dob: 65.years.ago..18.years.ago).count,
      "Over 65"  => @over_65
    }

    @users_by_department = User
      .joins(:address)
      .group("addresses.department_id")
      .count || {}

    # =======================================
    # PARTNER ANALYTICS
    # =======================================
    @partners_by_sector = Partner.group(:sector)
      .count
      .transform_keys { |k| k.presence || "Unknown" }

    @partners_with_logo = Partner.joins(logo_attachment: :blob).distinct

    @submissions_by_partner = IdentitySubmission
      .joins(:user)
      .group("users.partner_id")
      .count
      .transform_keys { |id| Partner.find_by(id: id)&.name || "Unknown" }

    # =======================================
    # OFFICER ANALYTICS
    # =======================================
    @officers_verified = Officer
      .joins(user: :identity_submissions)
      .where(identity_submissions: { status: "approved" })
      .distinct
      .count

    @officers_unverified = Officer
      .where.not(
        id: Officer
          .joins(user: :identity_submissions)
          .where(identity_submissions: { status: "approved" })
      )
      .count

    @officers_by_department = Officer
      .joins(user: :address)
      .group("addresses.department_id")
      .count

    @officers_by_sex = Officer
      .joins(:user)
      .group("users.sex")
      .count

    @officers_under_35 = Officer
      .joins(:user)
      .where("users.dob > ?", 35.years.ago)
      .count

    @officers_over_54 = Officer
      .joins(:user)
      .where("users.dob < ?", 55.years.ago)
      .count
  end


  # ============================================================
  # EXPORT: USERS CSV + PDF
  # ============================================================
  def export_users_csv
    data = User.includes(:address)

    csv = CSV.generate(headers: true) do |csv|
      csv << %w[id full_name sex dob department]
      data.each do |u|
        csv << [
          u.id,
          u.full_name,
          u.sex,
          u.dob,
          u.address&.department_id
        ]
      end
    end

    send_data csv, filename: "bonid_users_#{Date.today}.csv"
  end

  def export_users_pdf
    pdf = Prawn::Document.new
    pdf.text "BonID Users Report", size: 24, style: :bold
    pdf.move_down 15

    User.limit(200).each do |u|
      pdf.text "#{u.full_name} • #{u.sex} • #{u.dob}"
    end

    send_data pdf.render,
              filename: "bonid_users_#{Date.today}.pdf",
              type: "application/pdf"
  end

  # ============================================================
  # EXPORT: OFFICERS CSV + PDF (ADD WHEN READY)
  # ============================================================
  # def export_officers_csv
  # def export_officers_pdf
  # def export_partners_csv
  # def export_partners_pdf
  # def export_verifications_csv
  # def export_verifications_pdf
end
