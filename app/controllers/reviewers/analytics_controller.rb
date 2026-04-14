# frozen_string_literal: true

module Reviewers
  class AnalyticsController < Reviewers::ApplicationController
    def index
      submissions = IdentitySubmission.all
      total = submissions.count

      # ── Volume trends (Chartkick-ready hashes) ──
      @submissions_daily   = submissions.group_by_day(:created_at, last: 30).count
      @submissions_weekly  = submissions.group_by_week(:created_at, last: 12).count
      @submissions_monthly = submissions.group_by_month(:created_at, last: 12).count

      # ── Approval / Rejection rates ──
      @approval_rate = total.positive? ? (submissions.approved.count.to_f / total * 100).round(1) : 0
      @rejection_rate = total.positive? ? (submissions.rejected.count.to_f / total * 100).round(1) : 0
      @pending_rate = total.positive? ? (submissions.pending.count.to_f / total * 100).round(1) : 0

      # ── Status breakdown (pie chart) ──
      @status_breakdown = {
        "Approved" => submissions.approved.count,
        "Rejected" => submissions.rejected.count,
        "Pending"  => submissions.pending.count,
        "Revoked"  => submissions.revoked.count
      }

      # ── Top rejection reasons ──
      @rejection_reasons = submissions.rejected
        .where.not(rejection_reason: [nil, ""])
        .group(:rejection_reason)
        .order(Arel.sql("count(*) DESC"))
        .limit(10)
        .count
        .transform_keys { |k| k.to_s.humanize }

      # ── Double Lock fraud metrics ──
      fraud_scope = submissions.where(status: :rejected, rejection_reason: "duplicate_identity")

      @fraud_total        = fraud_scope.count
      @fraud_last_30_days = fraud_scope.where("created_at > ?", 30.days.ago).count
      @fraud_last_7_days  = fraud_scope.where("created_at > ?", 7.days.ago).count
      @fraud_trend        = fraud_scope.group_by_day(:created_at, last: 30).count

      # ── Submission type breakdown ──
      @type_breakdown = {
        "Initial"      => submissions.where(submission_type: :initial).count,
        "Resubmission" => submissions.where(submission_type: :resubmission).count,
        "Reissue"      => submissions.where(submission_type: :reissue).count,
        "Visitor"      => submissions.where(submission_type: :visitor).count
      }

      # ── Reviewer performance (who reviewed what) ──
      @reviews_by_reviewer = submissions
        .where.not(reviewed_by: nil)
        .group(:reviewed_by)
        .count
        .transform_keys { |id| User.find_by(id: id)&.full_name || "Unknown (##{id})" }

      # ── Counts for stat cards ──
      @total_submissions = total
      @pending_count     = submissions.pending.count
      @approved_count    = submissions.approved.count
      @rejected_count    = submissions.rejected.count

      # ── Demographics (scoped to submitters) ──
      submitter_ids = submissions.select(:user_id).distinct
      submitters = User.where(id: submitter_ids)

      @gender_breakdown = submitters.group(:sex).count.transform_keys { |k| k.presence || "Non Espesifye" }

      @age_groups = {
        "Mwens ke 18"  => submitters.where("dob > ?", 18.years.ago).count,
        "18–35"        => submitters.where(dob: 35.years.ago..18.years.ago).count,
        "36–65"        => submitters.where(dob: 65.years.ago..35.years.ago).count,
        "Plis ke 65"   => submitters.where("dob < ?", 65.years.ago).count
      }

      # ── Geographic distribution ──
      @by_department = submitters
        .joins(:address)
        .group("addresses.department_id")
        .count
        .transform_keys { |id| Department.find_by(id: id)&.name || "Enkoni (##{id})" }

      @by_commune = submitters
        .joins(:address)
        .where.not(addresses: { commune_id: nil })
        .group("addresses.commune_id")
        .order(Arel.sql("count(*) DESC"))
        .limit(15)
        .count
        .transform_keys { |id| Commune.find_by(id: id)&.name || "Enkoni (##{id})" }
    end
  end
end
