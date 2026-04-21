# frozen_string_literal: true

# Returns the citizen-sidebar election links for BonVote v1.
#
# Scope per 2026-04-20 reframe (project_election_v1_scope memory):
# v1 is verify + register voters only. Vote-casting, receipt verification,
# and results are all paused behind FEATURE_BONVOTE_TALLY. Those links
# used to live here; they're now omitted entirely until the tally stack
# is unshelved.
#
# Remaining links:
#   - "Eleksyon Mwen" → enrollment state page (the core action)
#   - "Kalandriye"    → read-only registration deadline calendar
#
# Usage from a view:
#   CitizenElectionSidebarPresenter.for_today.links.each { |link| render link }
class CitizenElectionSidebarPresenter
  include Rails.application.routes.url_helpers

  Link = Struct.new(:path, :icon, :label, :badge, :badge_class, :active_match, keyword_init: true)

  # Pick the election most relevant for a citizen *right now*:
  # open election if one exists, otherwise the nearest upcoming draft,
  # otherwise the most recently-closed election.
  def self.for_today
    election =
      BonvoteElection.find_by(status: "open") ||
      BonvoteElection.where(status: "draft").order(election_date: :asc).first ||
      BonvoteElection.order(election_date: :desc).first
    new(election)
  end

  def initialize(election)
    @election = election
  end

  # v1 surface: just the two registration-lifecycle links. Order is
  # stable across election statuses because there's nothing to reorder
  # — enrollment is always the primary action in v1.
  def links
    [
      enrollment_link(badge: enrollment_badge, badge_class: "sidebar-badge--amber"),
      calendar_link
    ]
  end

  private

  attr_reader :election

  def enrollment_link(**overrides)
    Link.new(
      path: citizens_election_enrollment_path,
      icon: "ri-user-voice-line",
      label: "Anrejistre",
      active_match: "election/enskri",
      badge: nil, badge_class: nil
    ).tap { |l| overrides.each { |k, v| l[k] = v } }
  end

  def calendar_link(**overrides)
    Link.new(
      path: citizens_election_calendar_path,
      icon: "ri-calendar-event-line",
      label: "Kalandriye",
      active_match: "election/kalandriye",
      badge: nil, badge_class: nil
    ).tap { |l| overrides.each { |k, v| l[k] = v } }
  end

  # Countdown to the election date, shown on the enrollment link so every
  # login reinforces the registration deadline. "Jodi a" / "Demen" / "nan N jou".
  def enrollment_badge
    return nil unless election&.election_date

    days = (election.election_date - Date.current).to_i
    case days
    when ..-1 then nil
    when 0    then "Jodi a"
    when 1    then "Demen"
    else           "nan #{days} jou"
    end
  end
end
