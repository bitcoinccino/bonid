# frozen_string_literal: true

# Ajan::AnalyticsController
# =========================
# Agent-facing analytics for the partner they belong to. Scoped to lookup /
# scan activity the agent's partner has generated. Deliberately narrow —
# agents don't get the full partner-admin analytics surface (fiscal, payments,
# reconciliation) until those are explicitly asked for.
module Ajan
  class AnalyticsController < Ajan::ApplicationController
    def index
      @partner = current_partner

      scans       = @partner.qr_scans
      today_scans = scans.where("created_at >= ?", Time.current.beginning_of_day)

      @stats = {
        total_scans:   scans.count,
        scans_today:   today_scans.count,
        scans_mine:    scans.where("metadata->>'agent_id' = ?", current_agent.id.to_s).count,
        mismatches:    @partner.partner_audit_logs.where(event: "identity_mismatch").count
      }

      @scans_by_day = scans
        .where("created_at >= ?", 14.days.ago)
        .group("DATE(created_at)")
        .order("DATE(created_at)")
        .count

      @recent_scans = scans
        .includes(identity_submission: :user)
        .order(created_at: :desc)
        .limit(20)

      return unless current_sector == "cep"

      election = BonvoteElection.where(status: "active").order(created_at: :desc).first ||
                 BonvoteElection.order(created_at: :desc).first
      return unless election

      partner_enrollments = VoterEligibilityRecord
        .where(bonvote_election: election, registered_by_partner_id: @partner.id)

      @voter_stats = {
        election_title:   election.title,
        partner_enrolled: partner_enrollments.eligible.count,
        today_enrolled:   partner_enrollments.where("registered_at >= ?", Time.current.beginning_of_day).count
      }
    end
  end
end
