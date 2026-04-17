# frozen_string_literal: true

# Returns the citizen-sidebar election links in an order keyed to the
# election's current lifecycle state. Also annotates the "Vote" link with
# a live countdown badge so every login reinforces the election date.
#
# Usage from a view (or helper):
#
#   presenter = CitizenElectionSidebarPresenter.for_today
#   presenter.links.each { |link| render link }
#
# Each link is a struct with: path, icon, label, badge (or nil),
# badge_class (or nil), active_match (a string fragment used to set
# `active` class on the nav-link).
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

  def links
    case @election&.status
    when "open"      then links_open
    when "closed"    then links_closed
    when "certified" then links_certified
    else                  links_upcoming # draft, cancelled, or nil
    end
  end

  private

  attr_reader :election

  # Before the polls open: the only real action is enroll + watch the
  # calendar. "Vote" sits last with a days-until badge.
  def links_upcoming
    [
      enrollment_link,
      calendar_link,
      vote_link(badge: countdown_badge, badge_class: "sidebar-badge--amber"),
      verify_link,
      results_link
    ]
  end

  # Polls are open: the only action that matters is Vote.
  def links_open
    [
      vote_link(badge: "LOUVRI", badge_class: "sidebar-badge--live"),
      enrollment_link,
      calendar_link,
      verify_link,
      results_link
    ]
  end

  # Polls closed, awaiting certification: citizens want to verify their vote.
  def links_closed
    [
      verify_link(badge: "Fèmen", badge_class: "sidebar-badge--muted"),
      results_link,
      calendar_link,
      enrollment_link,
      vote_link
    ]
  end

  # Certified: results are official. Surface them first.
  def links_certified
    [
      results_link(badge: "Sètifye", badge_class: "sidebar-badge--success"),
      verify_link,
      calendar_link,
      enrollment_link,
      vote_link
    ]
  end

  # ── Link builders ────────────────────────────────────────
  def enrollment_link(**overrides)
    Link.new(
      path: citizens_election_enrollment_path,
      icon: "ri-user-voice-line",
      label: "Eleksyon Mwen",
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

  def vote_link(badge: nil, badge_class: nil)
    Link.new(
      path: citizens_election_vote_path,
      icon: "ri-checkbox-circle-line",
      label: "Vote",
      active_match: "election/vote",
      badge: badge, badge_class: badge_class
    )
  end

  def verify_link(badge: nil, badge_class: nil)
    Link.new(
      path: citizens_election_verify_path,
      icon: "ri-shield-check-line",
      label: "Verifye Vòt Mwen",
      active_match: "election/verifye",
      badge: badge, badge_class: badge_class
    )
  end

  def results_link(badge: nil, badge_class: nil)
    Link.new(
      path: citizens_election_results_path,
      icon: "ri-bar-chart-box-line",
      label: "Rezilta",
      active_match: "election/rezilta",
      badge: badge, badge_class: badge_class
    )
  end

  # "Nan 136 jou", "Demen", "Jodi a" — recomputed on every render so the
  # sidebar ticks down naturally across sessions.
  def countdown_badge
    return nil unless election&.election_date

    days = (election.election_date - Date.current).to_i
    case days
    when ..-1 then nil
    when 0    then "Jodi a"
    when 1    then "Demen"
    when 2..6 then "nan #{days} jou"
    else           "nan #{days} jou"
    end
  end
end
