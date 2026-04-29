# frozen_string_literal: true

module Citizens
  # Unified citizen Aktivite (activity) feed: consolidates QR scans,
  # consent grants, transaction consents, service applications, and
  # login sessions (Koneksyon).
  class ActivityController < BaseController
    TABS       = %w[all scans consents transactions applications sessions].freeze
    CATEGORIES = %w[all security financial administrative].freeze
    PER_PAGE   = 25
    TOP_N_PER_SOURCE_FOR_ALL_TAB = 50

    DEFAULT_WINDOW_DAYS = 30

    def index
      # Stamp first so the topbar bell renders with the new `seen_at` and
      # the badge clears on this same response. Update the in-memory record
      # via update_columns (skips callbacks/touch) and `current_citizen`
      # reflects the new value because update_columns mutates the loaded
      # attributes — no reload needed.
      current_citizen.update_columns(notifications_seen_at: Time.current)
      Citizens::AlertBroadcastJob.perform_later(current_citizen.id)

      @tab      = TABS.include?(params[:tab]) ? params[:tab] : "all"
      @filter   = CATEGORIES.include?(params[:filter]) ? params[:filter] : "all"
      @from, @to = normalized_date_range
      @counts   = activity_counts
      @events   = load_events_for_tab(@tab)

      @events = apply_category_filter(@events, @filter) unless @filter == "all"

      respond_to do |format|
        format.html
        format.pdf do
          render pdf: "BonID-Aktivite-#{Time.current.strftime('%Y%m%d')}",
                 template: "citizens/activity/index",
                 formats: [ :html ],
                 layout:   false,
                 locals:   { export_mode: true },
                 page_size: "A4",
                 margin:   { top: 15, bottom: 15, left: 12, right: 12 }
        end
      end
    end

    private

    # ------------------------------------------------------------
    # Pill badge counts — one cheap COUNT per source, scoped to the
    # same date window AND category filter as the events list. This
    # guarantees the pill number always matches what the user will
    # see when they switch to that tab (e.g. if the active category
    # is "Administratif", the Koneksyon pill reads 0, not the total
    # session count — because sessions are Sekirite, not Administratif).
    # ------------------------------------------------------------
    def activity_counts
      allow = ->(cat) { @filter == "all" || @filter == cat.to_s }

      scans    = allow.call(:security)       ? within_window(scan_logs_scope, :scanned_at).count            : 0
      grants   = allow.call(:administrative) ? consent_grant_events_in_window.size                          : 0
      txn      = allow.call(:financial)      ? within_window(transaction_consents_scope, :created_at).count : 0
      apps     = allow.call(:administrative) ? within_window(service_applications_scope, :updated_at).count : 0
      oaths    = allow.call(:administrative) ? within_window(oaths_scope, :accepted_at).count               : 0
      sessions = allow.call(:security)       ? within_window(sessions_scope, :created_at).count             : 0

      {
        scans:        scans,
        consents:     grants + txn,
        transactions: txn,
        applications: apps + oaths,
        sessions:     sessions
      }
    end

    # ------------------------------------------------------------
    # Date range handling
    # ------------------------------------------------------------
    def normalized_date_range
      from = parse_date(params[:from]) || DEFAULT_WINDOW_DAYS.days.ago.to_date
      to   = parse_date(params[:to])   || Date.current
      from, to = to, from if from > to
      [ from, to ]
    end

    def parse_date(raw)
      return nil if raw.blank?
      Date.parse(raw.to_s)
    rescue ArgumentError
      nil
    end

    def within_window(scope, column)
      scope.where(column => @from.beginning_of_day..@to.end_of_day)
    end

    # Each ConsentGrant fans out into one event per audit_log entry. Window
    # filtering uses the event timestamp, not the row's created_at, so a
    # grant first created months ago that gets re-approved today still
    # surfaces for today.
    def consent_grant_events_in_window
      @consent_grant_events_in_window ||= begin
        grants = consent_grants_scope.includes(partner: { logo_attachment: :blob })
        grants.flat_map { |g| CitizenActivityEvent.events_from_consent_grant(g) }
              .select  { |e| event_in_window?(e) }
              .sort_by { |e| e.timestamp || Time.at(0) }
              .reverse
      end
    end

    def event_in_window?(event)
      ts = event.timestamp
      return false if ts.blank?
      ts >= @from.beginning_of_day && ts <= @to.end_of_day
    end

    def apply_category_filter(events, filter)
      target = filter.to_sym
      events.select { |e| e.category == target }.then do |filtered|
        if events.respond_to?(:current_page)
          # Rewrap arrays that were paginated with Kaminari so the view helpers still work.
          Kaminari.paginate_array(filtered, total_count: filtered.size)
                  .page(events.current_page)
                  .per(events.limit_value)
        else
          filtered
        end
      end
    end

    # ------------------------------------------------------------
    # Per-tab loaders
    # ------------------------------------------------------------
    def load_events_for_tab(tab)
      case tab
      when "scans"        then load_scans
      when "consents"     then load_consents
      when "transactions" then load_transactions
      when "applications" then load_applications
      when "sessions"     then load_sessions
      else                     load_all
      end
    end

    def load_scans
      logs = within_window(scan_logs_scope, :scanned_at)
               .includes(:partner, qr_scan: :department)
               .order(scanned_at: :desc)
               .page(params[:page]).per(15)
      paginate_with_presenter(logs) { |l| CitizenActivityEvent.from_qr_scan(l) }
    end

    def load_consents
      grant_events = consent_grant_events_in_window
      txn = within_window(transaction_consents_scope, :created_at)
              .includes(partner: { logo_attachment: :blob })
              .order(created_at: :desc)
              .limit(100)

      merged = grant_events +
               txn.map { |t| CitizenActivityEvent.from_transaction_consent(t) }
      merged.sort_by! { |e| e.timestamp || Time.at(0) }.reverse!
      Kaminari.paginate_array(merged).page(params[:page]).per(20)
    end

    def load_transactions
      txn = within_window(transaction_consents_scope, :created_at)
              .includes(partner: { logo_attachment: :blob })
              .order(created_at: :desc)
              .page(params[:page]).per(15)
      paginate_with_presenter(txn) { |t| CitizenActivityEvent.from_transaction_consent(t) }
    end

    def load_applications
      apps = within_window(service_applications_scope, :updated_at)
               .includes(:partner, :partner_schema)
               .order(updated_at: :desc)
               .limit(100)
      oaths = within_window(oaths_scope, :accepted_at)
                .includes(:bonvote_election, :identity_submission)
                .order(accepted_at: :desc)
                .limit(100)

      merged = apps.map  { |a| CitizenActivityEvent.from_service_application(a) } +
               oaths.map { |o| CitizenActivityEvent.from_oath_acknowledgement(o) }
      merged.sort_by! { |e| e.timestamp || Time.at(0) }.reverse!
      Kaminari.paginate_array(merged).page(params[:page]).per(15)
    end

    def load_sessions
      list = within_window(sessions_scope, :created_at)
               .order(created_at: :desc)
               .page(params[:page]).per(15)

      new_device_map = build_new_device_map(list)
      paginate_with_presenter(list) do |s|
        CitizenActivityEvent.from_session(s, new_device: new_device_map[s.id])
      end
    end

    def load_all
      events = []

      within_window(scan_logs_scope, :scanned_at)
        .includes(:qr_scan, :partner)
        .order(scanned_at: :desc)
        .limit(TOP_N_PER_SOURCE_FOR_ALL_TAB)
        .each { |l| events << CitizenActivityEvent.from_qr_scan(l) }

      consent_grant_events_in_window
        .first(TOP_N_PER_SOURCE_FOR_ALL_TAB)
        .each { |e| events << e }

      within_window(transaction_consents_scope, :created_at)
        .includes(partner: { logo_attachment: :blob })
        .order(created_at: :desc)
        .limit(TOP_N_PER_SOURCE_FOR_ALL_TAB)
        .each { |t| events << CitizenActivityEvent.from_transaction_consent(t) }

      within_window(service_applications_scope, :updated_at)
        .includes(:partner, :partner_schema)
        .order(updated_at: :desc)
        .limit(TOP_N_PER_SOURCE_FOR_ALL_TAB)
        .each { |a| events << CitizenActivityEvent.from_service_application(a) }

      within_window(oaths_scope, :accepted_at)
        .includes(:bonvote_election, :identity_submission)
        .order(accepted_at: :desc)
        .limit(TOP_N_PER_SOURCE_FOR_ALL_TAB)
        .each { |o| events << CitizenActivityEvent.from_oath_acknowledgement(o) }

      session_logs = within_window(sessions_scope, :created_at)
                       .order(created_at: :desc)
                       .limit(TOP_N_PER_SOURCE_FOR_ALL_TAB)
                       .to_a
      new_device_map = build_new_device_map(session_logs)
      session_logs.each { |s| events << CitizenActivityEvent.from_session(s, new_device: new_device_map[s.id]) }

      events.sort_by! { |e| e.timestamp || Time.at(0) }.reverse!
      Kaminari.paginate_array(events).page(params[:page]).per(PER_PAGE)
    end

    # For each CitizenSession in the given list, determine whether it is the
    # citizen's earliest session ever from that IP. One batch query instead of
    # N+1 — the view will render a "new device" flag for any row where this is true.
    def build_new_device_map(sessions)
      ips = sessions.map(&:ip_address).compact.uniq
      return {} if ips.empty?

      first_by_ip = current_citizen.citizen_sessions
                                   .where(ip_address: ips)
                                   .group(:ip_address)
                                   .minimum(:created_at)

      sessions.each_with_object({}) do |s, h|
        h[s.id] = s.ip_address.present? && first_by_ip[s.ip_address] == s.created_at
      end
    end

    # ------------------------------------------------------------
    # Paginated AR relation → paginated presenter array
    # Preserves current_page/total_pages for Kaminari views.
    # ------------------------------------------------------------
    def paginate_with_presenter(relation)
      Kaminari.paginate_array(relation.map { |r| yield(r) }, total_count: relation.total_count)
              .page(relation.current_page)
              .per(relation.limit_value)
    end

    # ------------------------------------------------------------
    # Base scopes (citizen-scoped)
    # ------------------------------------------------------------
    # Hide PNH / law-enforcement scans from the citizen's own feed.
    # Citizens are intentionally not notified when police verify their
    # BonID — that would tip off the subject of an investigation.
    # Every other partner scan IS reported.
    LAW_ENFORCEMENT_SECTORS = %w[law_enforcement pnh].freeze

    def scan_logs_scope
      QrScanLog.joins(:identity_submission)
               .where(identity_submissions: { user_id: current_citizen.id })
               .where(officer_id: nil)
               .left_outer_joins(:partner)
               .where("partners.sector IS NULL OR partners.sector NOT IN (?)", LAW_ENFORCEMENT_SECTORS)
    end

    def consent_grants_scope
      current_citizen.consent_grants
    end

    def transaction_consents_scope
      current_citizen.transaction_consents
    end

    def service_applications_scope
      current_citizen.service_applications
    end

    def oaths_scope
      VoterOathAcknowledgement.where(user_id: current_citizen.id)
    end

    def sessions_scope
      current_citizen.citizen_sessions
    end
  end
end
