# frozen_string_literal: true

# The citizen notification bell.
#
# A notification is an event someone else (or the system) caused —
# see CitizenActivityEvent#notifiable?: QR scans, a partner asking for
# access, access expiring, transaction requests, application decisions.
# The citizen's own actions stay in the Activité feed but never count.
#
# Each notification is unread until the citizen opens it (a
# NotificationRead row) or presses "Mark all as read", which moves
# `notifications_seen_at` forward. Opening the bell or the Activité page
# doesn't change anything.
#
# CitizenSession is excluded — own-device logins would ring on every
# visit; new-device logins get their own email and show in Activité.
module Citizens
  class AlertCounter
    LAW_ENFORCEMENT_SECTORS = %w[law_enforcement pnh].freeze
    LOOKBACK   = 90.days
    PER_SOURCE = 50

    attr_reader :citizen, :since

    def initialize(citizen)
      @citizen = citizen
      # "Mark all as read" cutoff: anything at or before it is read.
      @since   = citizen.notifications_seen_at || citizen.created_at || Time.at(0)
    end

    # Unread notifications, for the red badge.
    def total
      notifications.count { |e| unread?(e) }
    end

    # Latest notifications, read or not, for the bell popover.
    def recent_events(limit: 5)
      notifications.first(limit)
    end

    def unread?(event)
      event.timestamp.present? && event.timestamp > since &&
        !read_keys.include?(event.notification_key)
    end

    private

    def notifications
      @notifications ||= (scan_events + consent_events + transaction_events + application_events)
        .select(&:notifiable?)
        .sort_by { |e| e.timestamp || Time.at(0) }
        .reverse
    end

    def read_keys
      @read_keys ||= citizen.notification_reads
                            .where(key: notifications.map(&:notification_key))
                            .pluck(:key)
                            .to_set
    end

    def window_start
      LOOKBACK.ago
    end

    def scan_events
      scan_logs_scope
        .where("qr_scan_logs.scanned_at >= ?", window_start)
        .includes(:partner, qr_scan: :department)
        .order(scanned_at: :desc)
        .limit(PER_SOURCE)
        .map { |l| CitizenActivityEvent.from_qr_scan(l) }
    end

    # updated_at moves when the status changes (request, grant, revoke,
    # expiry); partner reads and audit appends skip it on purpose.
    def consent_events
      citizen.consent_grants
        .where("updated_at >= ?", window_start)
        .includes(partner: { logo_attachment: :blob })
        .order(updated_at: :desc)
        .limit(PER_SOURCE)
        .flat_map { |g| CitizenActivityEvent.events_from_consent_grant(g) }
        .select { |e| e.timestamp.present? && e.timestamp >= window_start }
    end

    def transaction_events
      citizen.transaction_consents
        .where("updated_at >= ?", window_start)
        .includes(partner: { logo_attachment: :blob })
        .order(updated_at: :desc)
        .limit(PER_SOURCE)
        .map { |t| CitizenActivityEvent.from_transaction_consent(t) }
    end

    def application_events
      citizen.service_applications
        .where("updated_at >= ?", window_start)
        .includes(:partner, :partner_schema)
        .order(updated_at: :desc)
        .limit(PER_SOURCE)
        .map { |a| CitizenActivityEvent.from_service_application(a) }
    end

    def scan_logs_scope
      QrScanLog
        .joins(:identity_submission)
        .where(identity_submissions: { user_id: citizen.id })
        .where(officer_id: nil)
        .left_outer_joins(:partner)
        .where("partners.sector IS NULL OR partners.sector NOT IN (?)", LAW_ENFORCEMENT_SECTORS)
    end
  end
end
