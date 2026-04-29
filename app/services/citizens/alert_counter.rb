# frozen_string_literal: true

# Counts citizen-facing alerts (events newer than `notifications_seen_at`)
# across the same five sources the Aktivite feed surfaces. Used by both the
# topbar bell and the Aktivite tab pill counts so they always agree.
#
# CitizenSession is intentionally excluded from the bell — own-device logins
# would ring the bell on every visit. New-device alerts still surface in the
# Aktivite feed itself.
module Citizens
  class AlertCounter
    LAW_ENFORCEMENT_SECTORS = %w[law_enforcement pnh].freeze

    attr_reader :citizen, :since

    def initialize(citizen)
      @citizen = citizen
      @since   = citizen.notifications_seen_at || citizen.created_at || Time.at(0)
    end

    def total
      scans + consents + transactions + applications + oaths
    end

    def scans
      @scans ||= scan_logs_scope.where("qr_scan_logs.scanned_at > ?", since).count
    end

    # Latest events across all 5 sources, regardless of seen state. Used to
    # populate the topbar bell popover; mirrors what the Aktivite "all" tab
    # would show, just trimmed to the most recent N rows.
    def recent_events(limit: 5)
      scans_e = scan_logs_scope
        .includes(:partner, qr_scan: :department)
        .order(scanned_at: :desc)
        .limit(limit)
        .map { |l| CitizenActivityEvent.from_qr_scan(l) }

      consents_e = citizen.consent_grants
        .includes(partner: { logo_attachment: :blob })
        .order(updated_at: :desc)
        .limit(limit)
        .filter_map { |g| CitizenActivityEvent.events_from_consent_grant(g).last }

      txns_e = citizen.transaction_consents
        .includes(partner: { logo_attachment: :blob })
        .order(updated_at: :desc)
        .limit(limit)
        .map { |t| CitizenActivityEvent.from_transaction_consent(t) }

      apps_e = citizen.service_applications
        .includes(:partner, :partner_schema)
        .order(updated_at: :desc)
        .limit(limit)
        .map { |a| CitizenActivityEvent.from_service_application(a) }

      oaths_e = VoterOathAcknowledgement
        .where(user_id: citizen.id)
        .includes(:bonvote_election, :identity_submission)
        .order(accepted_at: :desc)
        .limit(limit)
        .map { |o| CitizenActivityEvent.from_oath_acknowledgement(o) }

      (scans_e + consents_e + txns_e + apps_e + oaths_e)
        .sort_by { |e| e.timestamp || Time.at(0) }
        .reverse
        .first(limit)
    end

    private

    def scan_logs_scope
      QrScanLog
        .joins(:identity_submission)
        .where(identity_submissions: { user_id: citizen.id })
        .where(officer_id: nil)
        .left_outer_joins(:partner)
        .where("partners.sector IS NULL OR partners.sector NOT IN (?)", LAW_ENFORCEMENT_SECTORS)
    end

    public

    # Uses `updated_at` so status flips (revoke / re-grant / expire / partner
    # decision) also ring the bell. ConsentGrant#record_access! and
    # ConsentGrant#append_audit! deliberately skip `updated_at` (via
    # update_columns and `save!(touch: false)`), so silent partner reads
    # and audit-log appends don't trigger the bell.
    def consents
      @consents ||= citizen.consent_grants.where("updated_at > ?", since).count
    end

    def transactions
      @transactions ||= citizen.transaction_consents.where("updated_at > ?", since).count
    end

    def applications
      @applications ||= citizen.service_applications.where("updated_at > ?", since).count
    end

    def oaths
      @oaths ||= VoterOathAcknowledgement
        .where(user_id: citizen.id)
        .where("accepted_at > ?", since)
        .count
    end

    def by_category
      {
        security:       scans,
        financial:      transactions,
        administrative: consents + applications + oaths
      }
    end
  end
end
