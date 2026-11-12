# frozen_string_literal: true

# Unified presenter wrapping any citizen-facing activity event (QR scan,
# consent, transaction, application) for the citizen Aktivite page.
#
# Titles are written as action-narrative sentences — e.g. "Ou retire aksè
# Zellus", "Ou di wi a Zellus pou 5,000 HTG" — so the feed reads like a
# natural audit diary, not a status table. All copy lives under
# citizen_portal.activity_event.* and renders in the current I18n.locale
# (the citizen's portal language).
#
# Each source model stays untouched. The controller hands in the record
# via one of the `from_*` factories; the view only touches the presenter
# interface (#kind, #icon, #title, #subtitle, #timestamp, #status,
# #status_color, #deep_link).
class CitizenActivityEvent
  include ActionView::Helpers::NumberHelper

  KINDS = %i[scan consent transaction application session oath].freeze

  # Category groupings used by the Phase 3 filter pills.
  # - security       → things that touched your identity (who scanned, who logged in)
  # - financial      → money movements
  # - administrative → permissions granted/revoked, applications, signed oaths
  CATEGORY_BY_KIND = {
    scan:         :security,
    session:      :security,
    transaction:  :financial,
    consent:      :administrative,
    application:  :administrative,
    oath:         :administrative
  }.freeze

  attr_reader :kind, :source_record, :timestamp

  def initialize(kind:, source_record:, timestamp:, icon:, title:, subtitle: nil,
                 status: nil, status_color: nil, deep_link: nil, event_data: nil)
    @kind          = kind
    @source_record = source_record
    @timestamp     = timestamp
    @icon          = icon
    @title         = title
    @subtitle      = subtitle
    @status        = status
    @status_color  = status_color
    @deep_link     = deep_link
    @event_data    = event_data
  end

  def icon;        @icon;        end
  def title;       @title.presence || self.class.tr("fallback_title"); end
  def subtitle;    @subtitle;    end
  def status;      @status;      end
  def status_color; @status_color; end
  def deep_link;   @deep_link;   end

  def category
    CATEGORY_BY_KIND[@kind]
  end

  # ------------------------------------------------------------
  # Detail rows for the expandable panel on each activity row.
  # Returns an array of [label, value] pairs. Blank values are dropped.
  # ------------------------------------------------------------
  def details
    rows = case @kind
    when :scan        then scan_detail_rows
    when :consent     then consent_detail_rows
    when :transaction then transaction_detail_rows
    when :application then application_detail_rows
    when :session     then session_detail_rows
    when :oath        then oath_detail_rows
    else                   []
    end
    rows.reject { |(_, v)| v.blank? }
  end

  # Shorthand for this presenter's translation namespace.
  def self.tr(key, **opts)
    I18n.t("citizen_portal.activity_event.#{key}", **opts)
  end

  def tr(key, **opts)
    self.class.tr(key, **opts)
  end

  # Localized month abbreviation (1-based month).
  def self.month_abbr(month)
    tr("months")[month - 1]
  end

  # Full absolute timestamp for the detail panel — e.g. "30 Mas 2026 a 14:32".
  def full_timestamp
    format_full_time(@timestamp)
  end

  private

  def format_full_time(t)
    return nil if t.blank?
    t = t.in_time_zone
    tr("full_time", day: t.day, month: self.class.month_abbr(t.month), year: t.year, time: t.strftime("%H:%M"))
  end

  def scan_detail_rows
    log = @source_record
    qr  = log.qr_scan
    [
      [ tr("rows.partner"),    log.organization.presence || log.partner&.name ],
      [ tr("rows.sector"),     log.partner&.sector&.humanize ],
      [ tr("rows.method"),     qr&.manual ? tr("rows.method_manual") : tr("rows.method_qr") ],
      [ tr("rows.commune"),    qr&.city.presence || log.city.presence ],
      [ tr("rows.department"), qr&.department&.name.presence || log.region.presence ],
      [ tr("rows.country"),    log.country.presence ],
      [ tr("rows.exact_date"), format_full_time(log.scanned_at || log.created_at) ]
    ]
  end

  def consent_detail_rows
    cg       = @source_record
    ev       = @event_data || {}
    details  = ev[:details] || {}
    ev_scope = Array(details["scopes"]).compact.join(", ").presence
    ev_reas  = details["reason"].to_s.presence
    [
      [ tr("rows.partner"),             cg.partner&.name ],
      [ tr("rows.action"),              ev[:action_label] ],
      [ tr("rows.access_at_time"),      ev_scope ],
      [ tr("rows.reason"),              ev_reas ],
      [ tr("rows.current_status"),      cg.status&.humanize ],
      [ tr("rows.access_requested"),    Array(cg.requested_scopes).compact.join(", ").presence ],
      [ tr("rows.access_granted"),      Array(cg.granted_scopes).compact.join(", ").presence ],
      [ tr("rows.first_consent"),       format_full_time(cg.created_at) ],
      [ tr("rows.last_granted"),        format_full_time(cg.granted_at) ],
      [ tr("rows.last_revoked"),        format_full_time(cg.revoked_at) ],
      [ tr("rows.expires"),             format_full_time(cg.expires_at) ],
      [ tr("rows.last_partner_access"), format_full_time(cg.last_accessed_at) ],
      [ tr("rows.access_count"),        cg.access_count.to_i.positive? ? cg.access_count.to_s : nil ]
    ]
  end

  def transaction_detail_rows
    tc = @source_record
    [
      [ tr("rows.partner"),     tc.partner&.name ],
      [ tr("rows.status"),      tc.status&.humanize ],
      [ tr("rows.amount"),      self.class.format_amount(tc) ],
      [ tr("rows.type"),        tc.transaction_type&.humanize ],
      [ tr("rows.description"), tc.description.presence ],
      [ tr("rows.reference"),   tc.reference_id.presence ],
      [ tr("rows.created"),     format_full_time(tc.created_at) ],
      [ tr("rows.decided"),     format_full_time(tc.decided_at) ],
      [ tr("rows.expires"),     format_full_time(tc.expires_at) ]
    ]
  end

  def application_detail_rows
    sa = @source_record
    [
      [ tr("rows.partner"),           sa.partner&.name ],
      [ tr("rows.form"),              sa.partner_schema&.name ],
      [ tr("rows.status"),            sa.status&.humanize ],
      [ tr("rows.verification_code"), sa.verification_code.presence ],
      [ tr("rows.paid"),              sa.paid ? tr("rows.yes") : tr("rows.no") ],
      [ tr("rows.submitted"),         format_full_time(sa.submitted_at) ],
      [ tr("rows.reviewed"),          format_full_time(sa.reviewed_at) ],
      [ tr("rows.last_update"),       format_full_time(sa.updated_at) ],
      [ tr("rows.rejection_reason"),  sa.rejection_reason.presence ]
    ]
  end

  def session_detail_rows
    cs = @source_record
    ua = cs.user_agent.to_s
    [
      [ tr("rows.device"),     cs.device_type.to_s.capitalize.presence ],
      [ tr("rows.browser"),    ua.present? ? ua.truncate(90) : nil ],
      [ tr("rows.ip_address"), cs.ip_address.presence ],
      [ tr("rows.city"),       cs.city.presence ],
      [ tr("rows.country"),    cs.country.presence ],
      [ tr("rows.source"),     humanized_login_source(cs.login_source) ],
      [ tr("rows.exact_date"), format_full_time(cs.created_at) ]
    ]
  end

  def oath_detail_rows
    oak = @source_record
    [
      [ tr("rows.election"),     oak.bonvote_election&.title.presence || tr("rows.election_number", id: oak.bonvote_election_id) ],
      [ tr("rows.oath_version"), oak.oath_version ],
      [ tr("rows.signed"),       format_full_time(oak.accepted_at) ],
      [ tr("rows.ip_address"),   oak.ip_address.presence ],
      [ tr("rows.fingerprint"),  oak.digest&.first(24) ],
      [ tr("rows.kyc"),          oak.identity_submission_id ? tr("rows.kyc_signature", id: oak.identity_submission_id) : nil ]
    ]
  end

  def humanized_login_source(src)
    return nil if src.blank?
    return tr("rows.partner_source", name: src.sub("partner:", "").titleize) if src.start_with?("partner:")
    src.humanize
  end

  public

  # Relative time label shown on each row.
  # Same-day  → "Jodi a a 10:45"
  # Yesterday → "Yè a 14:20"
  # ≤ 6 days  → "N jou de sa"
  # older     → "15 Me" (same year) or "15 Me 2024"
  def timestamp_label
    t     = timestamp.in_time_zone
    today = Time.current.in_time_zone.to_date
    date  = t.to_date
    days  = (today - date).to_i

    case days
    when 0        then tr("time.today_at", time: t.strftime("%H:%M"))
    when 1        then tr("time.yesterday_at", time: t.strftime("%H:%M"))
    when 2..6     then tr("time.days_ago", count: days)
    else               date_for_bucket(date)
    end
  end

  # Date bucket used for grouping — a Symbol for today/yesterday,
  # a Date otherwise. Equal buckets share a divider row.
  def date_bucket
    return :empty if timestamp.nil?
    date  = timestamp.in_time_zone.to_date
    today = Time.current.in_time_zone.to_date
    days  = (today - date).to_i
    return :today     if days == 0
    return :yesterday if days == 1
    date
  end

  # Divider label for a bucket returned by #date_bucket.
  def self.date_bucket_label(bucket)
    case bucket
    when :today     then tr("time.today")
    when :yesterday then tr("time.yesterday")
    when Date       then new_date_bucket_label(bucket)
    else                 ""
    end
  end

  def self.new_date_bucket_label(date)
    today = Time.current.in_time_zone.to_date
    month = month_abbr(date.month)
    if date.year == today.year
      tr("time.day_month", day: date.day, month: month)
    else
      tr("time.day_month_year", day: date.day, month: month, year: date.year)
    end
  end

  private

  def date_for_bucket(date)
    self.class.new_date_bucket_label(date)
  end

  public

  # ------------------------------------------------------------
  # Factories — one per source
  # ------------------------------------------------------------

  def self.from_qr_scan(log)
    org        = log.organization.presence || log.partner&.name.presence || tr("a_partner_capitalized")
    qr_scan    = log.qr_scan
    commune    = qr_scan&.city.presence || log.city.presence
    department = qr_scan&.department&.name.presence
    location   = [ commune, department ].compact.join(", ").presence

    # Plain wording: "scanned your QR" vs "looked up your BonID number".
    title = qr_scan&.manual ? tr("scan.looked_up", org: org) : tr("scan.scanned", org: org)
    title = tr("scan.with_location", title: title, location: location) if location

    new(
      kind:          :scan,
      source_record: log,
      timestamp:     log.scanned_at || log.created_at,
      icon:          qr_scan&.manual ? "ri-search-line" : "ri-qr-scan-2-line",
      title:         title,
      subtitle:      nil,
      status:        nil,
      status_color:  nil,
      deep_link:     Rails.application.routes.url_helpers.scan_history_citizens_identity_submissions_path
    )
  end

  # Returns one CitizenActivityEvent per entry in the ConsentGrant's audit_log
  # (granted, revoked, expired, status_change, …) so the citizen feed reads as a
  # full history. Falls back to a single derived event when audit_log is blank.
  def self.events_from_consent_grant(cg)
    partner_name = cg.partner&.name.presence || tr("a_partner")
    audit        = cg.audit_log.is_a?(Hash) ? cg.audit_log : {}

    return [ build_consent_event_from_state(cg, partner_name) ] if audit.blank?

    entries = audit.filter_map { |ts_key, payload|
      ts = parse_audit_timestamp(ts_key)
      next nil if ts.nil?
      [ ts, payload || {} ]
    }.sort_by(&:first)

    entries = collapse_status_change_dupes(entries)

    events = entries.filter_map { |ts, payload| build_consent_event_from_audit(cg, partner_name, ts, payload) }
    events.presence || [ build_consent_event_from_state(cg, partner_name) ]
  end

  def self.parse_audit_timestamp(key)
    Time.iso8601(key.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # grant!/revoke! call update! (which fires after_update_commit → status_change)
  # and then explicit append_audit!("granted"/"revoked") at the same wall-clock
  # second. Drop the status_change rows when an explicit action exists at the
  # same second so the feed doesn't double up.
  def self.collapse_status_change_dupes(entries)
    entries.group_by { |ts, _| ts.to_i }.flat_map { |_, group|
      explicit = group.find { |_, p| %w[granted revoked].include?(p["action"].to_s) }
      explicit ? [ explicit ] : group
    }.sort_by(&:first)
  end

  def self.build_consent_event_from_audit(cg, partner_name, ts, payload)
    action = payload["action"].to_s
    return nil if action == "soft_delete" # admin-only action; not citizen-facing

    details = payload["details"] || {}
    status  = payload["status"].to_s.presence || cg.status.to_s

    title, subtitle, action_label =
      case action
      when "granted"
        scopes = Array(details["scopes"]).compact
        sub    = scope_summary(scopes)
        [ tr("consent.granted", partner: partner_name), sub, tr("consent.action_granted") ]
      when "revoked"
        reason = details["reason"].to_s
        sub    = (reason.present? && reason != "Citizen revoked from dashboard" && reason != "Citizen denied consent") ? reason : nil
        [ tr("consent.revoked", partner: partner_name), sub, tr("consent.action_revoked") ]
      when "status_change"
        [ tr("consent.changed", partner: partner_name), nil, tr("consent.action_status_change") ]
      else
        [ tr("consent.changed", partner: partner_name), nil, action.humanize.presence ]
      end

    new(
      kind:          :consent,
      source_record: cg,
      timestamp:     ts,
      icon:          consent_icon_for(status),
      title:         title,
      subtitle:      subtitle,
      status:        nil,
      status_color:  consent_color_for(status),
      deep_link:     Rails.application.routes.url_helpers.citizens_consents_path,
      event_data:    { action: action, action_label: action_label, status: status, details: details }
    )
  end

  def self.build_consent_event_from_state(cg, partner_name)
    scopes = Array(cg.granted_scopes.presence || cg.requested_scopes)
    title = case cg.status
    when "approved" then tr("consent.granted", partner: partner_name)
    when "revoked"  then tr("consent.revoked", partner: partner_name)
    when "pending"  then tr("consent.pending", partner: partner_name)
    when "expired"  then tr("consent.expired", partner: partner_name)
    else                 tr("consent.changed", partner: partner_name)
    end
    subtitle = scope_summary(scopes)

    new(
      kind:          :consent,
      source_record: cg,
      timestamp:     cg.created_at,
      icon:          consent_icon_for(cg.status),
      title:         title,
      subtitle:      subtitle,
      status:        nil,
      status_color:  cg.status_theme[:css],
      deep_link:     Rails.application.routes.url_helpers.citizens_consents_path,
      event_data:    nil
    )
  end

  def self.consent_color_for(status)
    case status
    when "approved" then "success"
    when "pending"  then "warning"
    when "revoked"  then "danger"
    else                 "secondary"
    end
  end

  def self.from_transaction_consent(tc)
    partner_name = tc.partner&.name.presence || tr("a_partner")
    amount_str   = format_amount(tc)
    type_label   = tc.transaction_type&.humanize&.downcase

    # One plain sentence per outcome; amount first when there is one.
    for_amount = amount_str ? tr("transaction.for_amount", amount: amount_str) : ""
    title = case tc.status
    when "approved" then tr("transaction.approved", partner: partner_name, for_amount: for_amount)
    when "denied"   then tr("transaction.denied", partner: partner_name, for_amount: for_amount)
    when "pending"  then tr("transaction.pending", partner: partner_name, for_amount: for_amount)
    when "expired"  then tr("transaction.expired", partner: partner_name)
    else                 tr("transaction.changed", partner: partner_name)
    end

    # Subtitle: only add type if the title is amount-based (avoid redundancy)
    subtitle = if amount_str && type_label
                 type_label.capitalize
    end

    new(
      kind:          :transaction,
      source_record: tc,
      timestamp:     tc.created_at,
      icon:          transaction_icon_for(tc.status),
      title:         title,
      subtitle:      subtitle,
      status:        nil,
      status_color:  transaction_status_color(tc.status),
      deep_link:     Rails.application.routes.url_helpers.citizens_transaction_consents_path
    )
  end

  def self.from_service_application(sa)
    partner_name = sa.partner&.name.presence || tr("a_partner")
    form_name    = sa.partner_schema&.name.presence

    title = case sa.status
    when "draft"
              form_name ? tr("application.draft_for", form: form_name) : tr("application.draft")
    when "submitted"
              tr("application.submitted", partner: partner_name)
    when "under_review"
              tr("application.under_review", partner: partner_name)
    when "approved"
              tr("application.approved", partner: partner_name)
    when "rejected"
              tr("application.rejected", partner: partner_name)
    when "cancelled"
              tr("application.cancelled", partner: partner_name)
    else
              tr("application.updated", partner: partner_name)
    end

    subtitle = [ form_name, sa.verification_code ].compact.uniq.reject { |s| title.include?(s.to_s) }.join(" · ").presence

    new(
      kind:          :application,
      source_record: sa,
      timestamp:     sa.updated_at,
      icon:          "ri-file-list-3-line",
      title:         title,
      subtitle:      subtitle,
      status:        nil,
      status_color:  application_status_color(sa.status),
      deep_link:     Rails.application.routes.url_helpers.citizens_service_application_path(sa)
    )
  end

  # Session / login event. Accepts an optional `new_device` keyword so the
  # caller (controller) can precompute the "first time from this IP" flag in
  # one batch query instead of re-hitting the DB per row.
  def self.from_session(cs, new_device: nil)
    new_device = cs.new_device? if new_device.nil?
    device     = cs.device_type
    location   = [ cs.city.presence, cs.country.presence ].compact.join(", ").presence
    source     = humanize_login_source(cs.login_source)

    title = new_device ? tr("session.new_device") : tr("session.signed_in")

    subtitle_parts = []
    subtitle_parts << device.capitalize if device.present?
    subtitle_parts << location          if location.present?
    subtitle_parts << source            if source.present?
    subtitle = subtitle_parts.uniq.join(" · ").presence

    new(
      kind:          :session,
      source_record: cs,
      timestamp:     cs.created_at,
      icon:          new_device ? "ri-alert-line" : "ri-login-circle-line",
      title:         title,
      subtitle:      subtitle,
      status:        nil,
      status_color:  new_device ? "warning" : "secondary",
      deep_link:     nil
    )
  end

  # Signed-oath event — one per (citizen, election, oath_version).
  # Deep-linked to the oath page itself so citizens can re-read the
  # text they agreed to even after signing.
  def self.from_oath_acknowledgement(oak)
    election_label = oak.bonvote_election&.title.presence ||
                     tr("oath.election_year", year: oak.bonvote_election&.election_date&.year)
    new(
      kind:          :oath,
      source_record: oak,
      timestamp:     oak.accepted_at,
      icon:          "ri-quill-pen-line",
      title:         tr("oath.title", election: election_label),
      subtitle:      tr("oath.subtitle", version: oak.oath_version),
      status:        nil,
      status_color:  "success",
      deep_link:     Rails.application.routes.url_helpers.citizens_election_vote_oath_path
    )
  end

  # ------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------

  def self.humanize_login_source(src)
    return nil if src.blank?
    return tr("session.via", name: src.sub("partner:", "").titleize) if src.start_with?("partner:")
    nil # "citizen_portal" is the default — don't add noise
  end

  def self.format_amount(tc)
    return nil unless tc.amount.present? && tc.amount.to_f > 0
    currency = tc.currency.presence || "HTG"
    formatted = ActiveSupport::NumberHelper.number_to_delimited(tc.amount.to_f, delimiter: ",", separator: ".")
    # Trim trailing ".0" for whole numbers
    formatted = formatted.sub(/\.0+$/, "")
    "#{formatted} #{currency}"
  end

  # Plain names for what a partner can see (shown under access events),
  # keyed by scope under citizen_portal.activity_event.scopes.
  def self.scope_label(scope)
    key = scope.to_s.tr(":", "_")
    I18n.t("citizen_portal.activity_event.scopes.#{key}", default: scope.to_s.tr(":_", "  "))
  end

  def self.scope_summary(scopes)
    labels = Array(scopes).map(&:to_s).reject { |sc| sc == "openid" }.map { |sc| scope_label(sc) }
    return nil if labels.empty?
    tr("scope_summary", list: "#{labels.first(3).join(', ')}#{labels.size > 3 ? '…' : ''}")
  end

  def self.transaction_icon_for(status)
    case status
    when "approved" then "ri-checkbox-circle-line"
    when "denied"   then "ri-close-circle-line"
    when "pending"  then "ri-hourglass-line"
    when "expired"  then "ri-time-line"
    else                 "ri-exchange-funds-line"
    end
  end

  def self.consent_icon_for(status)
    case status
    when "approved" then "ri-lock-unlock-line"
    when "revoked"  then "ri-lock-line"
    when "pending"  then "ri-hourglass-line"
    when "expired"  then "ri-calendar-close-line"
    else                 "ri-id-card-line"
    end
  end

  def self.transaction_status_color(status)
    case status
    when "approved" then "success"
    when "denied"   then "danger"
    when "expired"  then "secondary"
    else                 "warning"
    end
  end

  def self.application_status_color(status)
    case status
    when "approved"     then "success"
    when "rejected"     then "danger"
    when "cancelled"    then "secondary"
    when "under_review" then "info"
    when "submitted"    then "primary"
    else                     "warning" # draft
    end
  end
end
