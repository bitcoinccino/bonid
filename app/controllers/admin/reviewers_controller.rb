# frozen_string_literal: true

# Admin::ReviewersController
# ===========================
# Reviewer invitation via BonID lookup (last 6 chars).
# Same flow as officer invitations — must have verified BonID.
#
# Flow:
#   1. Admin enters last 6 chars of BonID → lookup
#   2. System shows name, masked email, photo → confirm
#   3. Admin clicks "Invite" → role assigned, email sent
#
module Admin
  class ReviewersController < Admin::ApplicationController
    before_action :set_reviewer, only: [ :destroy ]

    # ─────────────────────────────────────────────────────────
    # INDEX — List all reviewers
    # ─────────────────────────────────────────────────────────
    def index
      @reviewers = User.with_role(:reviewer).includes(:identity_submissions).order(created_at: :desc)
    end

    # ─────────────────────────────────────────────────────────
    # NEW — BonID lookup form
    # ─────────────────────────────────────────────────────────
    def new; end

    # ─────────────────────────────────────────────────────────
    # LOOKUP — Find user by last 6 chars of BonID
    # ─────────────────────────────────────────────────────────
    def lookup
      bonid_suffix = params[:bonid].to_s.strip.delete("-").upcase

      if bonid_suffix.blank?
        flash[:alert] = "Tanpri antre dènye 6 karaktè BonID a."
        return redirect_to new_admin_reviewer_path
      end

      @person = TeamInvitationService.lookup(bonid_suffix)

      if @person.nil?
        flash[:alert] = "Pa gen moun ak BonID ki fini ak \"#{bonid_suffix}\". Verifye kòd la epi eseye ankò."
        return redirect_to new_admin_reviewer_path
      end

      unless @person[:verified]
        flash[:alert] = "#{@person[:full_name]} gen yon kont BonID men li poko verifye. Yo dwe gen yon BonID apwouve anvan yo ka envite."
        return redirect_to new_admin_reviewer_path
      end

      @bonid_suffix = bonid_suffix
      render :confirm
    end

    # ─────────────────────────────────────────────────────────
    # CREATE — Assign reviewer role + send invitation
    # ─────────────────────────────────────────────────────────
    def create
      bonid_suffix = params[:bonid].to_s.strip.delete("-").upcase
      user = TeamInvitationService.find_by_suffix(bonid_suffix)

      unless user
        flash[:alert] = "Pa gen moun ak BonID sa a."
        return redirect_to new_admin_reviewer_path
      end

      unless user.identity_submissions.approved.exists?
        flash[:alert] = "#{user.full_name} pa gen yon BonID verifye."
        return redirect_to new_admin_reviewer_path
      end

      if user.has_role?(:reviewer)
        flash[:alert] = "#{user.full_name} deja yon Reviewer."
        return redirect_to admin_reviewers_path
      end

      ActiveRecord::Base.transaction do
        user.add_role(:reviewer)

        # Notification only — no invitation token needed.
        # Reviewers are existing BonID users; they already have credentials.
        # We just grant the role and tell them to sign in at /reviewer/sign_in.
        TeamMailer.role_granted(
          user: user,
          role: "reviewer"
        ).deliver_later

        PartnerAuditLog.log!(
          nil,
          current_admin_user,
          "reviewer_invited",
          {
            email:    user.email,
            name:     user.full_name,
            bonid:    user.bonid,
            method:   "bonid_lookup"
          }
        )
      end

      redirect_to admin_reviewers_path,
        notice: "Envitasyon voye bay #{user.full_name} (#{user.bonid})."
    end

    # ─────────────────────────────────────────────────────────
    # BULK — Upload CSV of BonID suffixes
    # ─────────────────────────────────────────────────────────
    def bulk_new; end

    def bulk_create
      file = params[:csv]

      unless file&.content_type&.in?(%w[text/csv application/csv application/vnd.ms-excel])
        return redirect_to bulk_new_admin_reviewers_path,
          alert: "Tanpri upload yon CSV valid."
      end

      invited = 0
      skipped_no_bonid = 0
      skipped_not_found = 0
      skipped_already = 0

      require "csv"
      CSV.foreach(file.path, headers: false) do |row|
        bonid_suffix = row.first.to_s.strip.delete("-").upcase
        next if bonid_suffix.blank?

        user = TeamInvitationService.find_by_suffix(bonid_suffix)

        if user.nil?
          skipped_not_found += 1
          next
        end

        unless user.identity_submissions.approved.exists?
          skipped_no_bonid += 1
          next
        end

        if user.has_role?(:reviewer)
          skipped_already += 1
          next
        end

        user.add_role(:reviewer)
        TeamMailer.role_granted(user: user, role: "reviewer").deliver_later
        invited += 1
      end

      PartnerAuditLog.log!(
        nil,
        current_admin_user,
        "reviewers_bulk_invited",
        { count: invited, method: "bonid_csv" }
      )

      flash[:notice] = "#{invited} reviewer(s) envite."
      if skipped_no_bonid > 0 || skipped_not_found > 0 || skipped_already > 0
        flash[:alert] = "#{skipped_not_found} pa jwenn, #{skipped_no_bonid} pa gen BonID verifye, #{skipped_already} deja reviewer."
      end

      redirect_to admin_reviewers_path
    end

    # ─────────────────────────────────────────────────────────
    # ACTIVITY — Reviewer pulse dashboard (admin monitoring)
    # ─────────────────────────────────────────────────────────
    def activity
      @reviewers = User.with_role(:reviewer).includes(:identity_submissions)

      # Reviewer pulse: status, last login, session duration, stats
      @reviewer_stats = @reviewers.map do |reviewer|
        last_login = ReviewerActivity.for_reviewer(reviewer.id).logins.recent.first
        activities_today = ReviewerActivity.for_reviewer(reviewer.id).today

        {
          user:              reviewer,
          online:            reviewer.last_seen_at.present? && reviewer.last_seen_at > 5.minutes.ago,
          idle:              reviewer.last_seen_at.present? && reviewer.last_seen_at.between?(15.minutes.ago, 5.minutes.ago),
          last_login_at:     last_login&.created_at,
          last_login_ip:     last_login&.ip_address,
          current_ip:        reviewer.current_sign_in_ip,
          last_ip:           reviewer.last_sign_in_ip,
          ip_mismatch:       reviewer.current_sign_in_ip.present? &&
                             reviewer.last_sign_in_ip.present? &&
                             reviewer.current_sign_in_ip != reviewer.last_sign_in_ip,
          approvals_today:   activities_today.approvals.count,
          rejections_today:  activities_today.rejections.count,
          views_today:       activities_today.views.count,
          overrides_total:   ReviewerActivity.for_reviewer(reviewer.id).overrides.count,
          total_reviews:     ReviewerActivity.for_reviewer(reviewer.id).reviews.count
        }
      end

      # Recent activity feed (all reviewers)
      @recent_activities = ReviewerActivity
        .includes(:user, :target)
        .recent
        .limit(50)

      # Aggregate stats
      @total_reviews_today = ReviewerActivity.today.reviews.count
      @total_overrides     = ReviewerActivity.overrides.count
      @active_reviewers    = @reviewer_stats.count { |r| r[:online] }
    end

    # ─────────────────────────────────────────────────────────
    # DESTROY — Remove reviewer role
    # ─────────────────────────────────────────────────────────
    def destroy
      @reviewer.remove_role(:reviewer)

      PartnerAuditLog.log!(
        nil,
        current_admin_user,
        "reviewer_removed",
        { email: @reviewer.email, bonid: @reviewer.bonid }
      )

      redirect_to admin_reviewers_path,
        notice: "Reviewer #{@reviewer.full_name} retire."
    end

    private

    def set_reviewer
      @reviewer = User.find(params[:id])
    end
  end
end
