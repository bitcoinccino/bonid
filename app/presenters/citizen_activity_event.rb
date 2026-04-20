# frozen_string_literal: true

# Unified presenter wrapping any citizen-facing activity event (QR scan,
# consent, transaction, application) for the citizen Aktivite page.
#
# Titles are written as action-narrative Haitian Creole sentences — e.g.
# "Ou revoke aksè pou Zellus", "Ou apwouve yon tranzaksyon pou 5,000 HTG" —
# so the feed reads like a natural audit diary, not a status table.
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
                 status: nil, status_color: nil, deep_link: nil)
    @kind          = kind
    @source_record = source_record
    @timestamp     = timestamp
    @icon          = icon
    @title         = title
    @subtitle      = subtitle
    @status        = status
    @status_color  = status_color
    @deep_link     = deep_link
  end

  def icon;        @icon;        end
  def title;       @title.presence || "Aktivite"; end
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

  # Full absolute timestamp for the detail panel — e.g. "30 Mas 2026 a 14:32".
  def full_timestamp
    format_full_time(@timestamp)
  end

  private

  def format_full_time(t)
    return nil if t.blank?
    t = t.in_time_zone
    month = HT_MONTHS[t.month - 1]
    "#{t.day} #{month} #{t.year} a #{t.strftime('%H:%M')}"
  end

  def scan_detail_rows
    log = @source_record
    qr  = log.qr_scan
    [
      [ "Patnè",      log.organization.presence || log.partner&.name ],
      [ "Sektè",      log.partner&.sector&.humanize ],
      [ "Metòd",      qr&.manual ? "Manyèl (kòd tape)" : "QR (eskan)" ],
      [ "Komin",      qr&.city.presence || log.city.presence ],
      [ "Depatman",   qr&.department&.name.presence || log.region.presence ],
      [ "Peyi",       log.country.presence ],
      [ "Dat egzak",  format_full_time(log.scanned_at || log.created_at) ]
    ]
  end

  def consent_detail_rows
    cg = @source_record
    [
      [ "Patnè",        cg.partner&.name ],
      [ "Statè",        cg.status&.humanize ],
      [ "Aksè mande",   Array(cg.requested_scopes).compact.join(", ").presence ],
      [ "Aksè bay",     Array(cg.granted_scopes).compact.join(", ").presence ],
      [ "Kreye",        format_full_time(cg.created_at) ],
      [ "Bay",          format_full_time(cg.granted_at) ],
      [ "Revoke",       format_full_time(cg.revoked_at) ],
      [ "Ekspire",      format_full_time(cg.expires_at) ],
      [ "Dènye aksè",   format_full_time(cg.last_accessed_at) ],
      [ "Kantite aksè", cg.access_count.to_i.positive? ? cg.access_count.to_s : nil ]
    ]
  end

  def transaction_detail_rows
    tc = @source_record
    [
      [ "Patnè",        tc.partner&.name ],
      [ "Statè",        tc.status&.humanize ],
      [ "Montan",       self.class.format_amount(tc) ],
      [ "Kalite",       tc.transaction_type&.humanize ],
      [ "Deskripsyon",  tc.description.presence ],
      [ "Referans",     tc.reference_id.presence ],
      [ "Kreye",        format_full_time(tc.created_at) ],
      [ "Desizyon",     format_full_time(tc.decided_at) ],
      [ "Ekspire",      format_full_time(tc.expires_at) ]
    ]
  end

  def application_detail_rows
    sa = @source_record
    [
      [ "Patnè",          sa.partner&.name ],
      [ "Fòm",            sa.partner_schema&.name ],
      [ "Statè",          sa.status&.humanize ],
      [ "Kòd verifikasyon", sa.verification_code.presence ],
      [ "Peye",           sa.paid ? "Wi" : "Non" ],
      [ "Soumèt",         format_full_time(sa.submitted_at) ],
      [ "Revize",         format_full_time(sa.reviewed_at) ],
      [ "Dènye mizajou",  format_full_time(sa.updated_at) ],
      [ "Rezon refi",     sa.rejection_reason.presence ]
    ]
  end

  def session_detail_rows
    cs = @source_record
    ua = cs.user_agent.to_s
    [
      [ "Aparèy",    cs.device_type.to_s.capitalize.presence ],
      [ "Navigatè",  ua.present? ? ua.truncate(90) : nil ],
      [ "Adrès IP",  cs.ip_address.presence ],
      [ "Vil",       cs.city.presence ],
      [ "Peyi",      cs.country.presence ],
      [ "Sous",      humanized_login_source(cs.login_source) ],
      [ "Dat egzak", format_full_time(cs.created_at) ]
    ]
  end

  def oath_detail_rows
    oak = @source_record
    [
      [ "Eleksyon",   oak.bonvote_election&.title.presence || "Eleksyon ##{oak.bonvote_election_id}" ],
      [ "Vèsyon sèman", oak.oath_version ],
      [ "Siyen",      format_full_time(oak.accepted_at) ],
      [ "Adrès IP",   oak.ip_address.presence ],
      [ "Anprent",    oak.digest&.first(24) ],
      [ "KYC BonID",  oak.identity_submission_id ? "Siyati BonID ##{oak.identity_submission_id}" : nil ]
    ]
  end

  def humanized_login_source(src)
    return nil if src.blank?
    return "Patnè · #{src.sub('partner:', '').titleize}" if src.start_with?("partner:")
    src.humanize
  end

  public

  # Haitian Creole month abbreviations (Jan, Fev, Mas, …)
  HT_MONTHS = %w[Jan Fev Mas Avr Me Jen Jiy Out Sep Okt Nov Des].freeze

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
    when 0        then "Jodi a a #{t.strftime('%H:%M')}"
    when 1        then "Yè a #{t.strftime('%H:%M')}"
    when 2..6     then "#{days} jou de sa"
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
    when :today     then "Jodi a"
    when :yesterday then "Yè"
    when Date       then new_date_bucket_label(bucket)
    else                 ""
    end
  end

  def self.new_date_bucket_label(date)
    today = Time.current.in_time_zone.to_date
    month = HT_MONTHS[date.month - 1]
    date.year == today.year ? "#{date.day} #{month}" : "#{date.day} #{month} #{date.year}"
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
    org        = log.organization.presence || log.partner&.name.presence || "Yon patnè"
    qr_scan    = log.qr_scan
    method     = qr_scan&.manual ? "manyèl" : "QR"
    commune    = qr_scan&.city.presence || log.city.presence
    department = qr_scan&.department&.name.presence
    location   = [ commune, department ].compact.join(", ").presence

    title = "#{org} eskane (#{method}) BonID ou"
    title += " nan #{location}" if location

    new(
      kind:          :scan,
      source_record: log,
      timestamp:     log.scanned_at || log.created_at,
      icon:          qr_scan&.manual ? "ri-keyboard-box-line" : "ri-qr-scan-2-line",
      title:         title,
      subtitle:      nil,
      status:        nil,
      status_color:  nil,
      deep_link:     Rails.application.routes.url_helpers.scan_history_citizens_identity_submissions_path
    )
  end

  def self.from_consent_grant(cg)
    partner_name = cg.partner&.name.presence || "yon patnè"
    scopes       = Array(cg.granted_scopes.presence || cg.requested_scopes)

    title = case cg.status
    when "approved" then "Ou bay #{partner_name} aksè a done ou yo"
    when "revoked"  then "Ou revoke aksè pou #{partner_name}"
    when "pending"  then "#{partner_name} mande aksè a done ou yo"
    when "expired"  then "Aksè #{partner_name} ekspire"
    else                 "Mizajou konsantman pou #{partner_name}"
    end

    subtitle = if scopes.any?
                 "Aksè: #{scopes.first(3).join(', ')}#{scopes.size > 3 ? '…' : ''}"
    end

    theme = cg.status_theme
    new(
      kind:          :consent,
      source_record: cg,
      timestamp:     cg.created_at,
      icon:          consent_icon_for(cg.status),
      title:         title,
      subtitle:      subtitle,
      status:        nil,
      status_color:  theme[:css],
      deep_link:     Rails.application.routes.url_helpers.citizens_consents_path
    )
  end

  def self.from_transaction_consent(tc)
    partner_name = tc.partner&.name.presence || "yon patnè"
    amount_str   = format_amount(tc)
    type_label   = tc.transaction_type&.humanize&.downcase

    title = case tc.status
    when "approved"
              if amount_str
                "Ou apwouve yon tranzaksyon pou #{amount_str} ak #{partner_name}"
              else
                "Ou apwouve yon #{type_label || 'tranzaksyon'} ak #{partner_name}"
              end
    when "denied"
              if amount_str
                "Ou refize yon tranzaksyon pou #{amount_str} ak #{partner_name}"
              else
                "Ou refize yon tranzaksyon ak #{partner_name}"
              end
    when "pending"
              if amount_str
                "#{partner_name} mande yon tranzaksyon pou #{amount_str}"
              else
                "#{partner_name} mande yon #{type_label || 'tranzaksyon'}"
              end
    when "expired"
              "Yon demand tranzaksyon ak #{partner_name} ekspire"
    else
              "Mizajou tranzaksyon ak #{partner_name}"
    end

    # Subtitle: only add type if the title is amount-based (avoid redundancy)
    subtitle = if amount_str && type_label
                 type_label.capitalize
    end

    new(
      kind:          :transaction,
      source_record: tc,
      timestamp:     tc.created_at,
      icon:          "ri-exchange-funds-line",
      title:         title,
      subtitle:      subtitle,
      status:        nil,
      status_color:  transaction_status_color(tc.status),
      deep_link:     Rails.application.routes.url_helpers.citizens_transaction_consents_path
    )
  end

  def self.from_service_application(sa)
    partner_name = sa.partner&.name.presence || "yon patnè"
    form_name    = sa.partner_schema&.name.presence

    title = case sa.status
    when "draft"
              form_name ? "Ou gen yon bouyon pou #{form_name}" : "Ou gen yon bouyon aplikasyon"
    when "submitted"
              "Ou soumèt yon aplikasyon bay #{partner_name}"
    when "under_review"
              "Aplikasyon ou ap revize pa #{partner_name}"
    when "approved"
              "#{partner_name} apwouve aplikasyon ou"
    when "rejected"
              "#{partner_name} rejte aplikasyon ou"
    when "cancelled"
              "Ou anile yon aplikasyon ak #{partner_name}"
    else
              "Mizajou aplikasyon ak #{partner_name}"
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

    title = new_device ? "Nouvo aparèy konekte sou BonID ou" : "Ou konekte sou BonID ou"

    subtitle_parts = []
    subtitle_parts << device.capitalize if device.present?
    subtitle_parts << location          if location.present?
    subtitle_parts << source            if source.present?
    subtitle = subtitle_parts.uniq.join(" · ").presence

    new(
      kind:          :session,
      source_record: cs,
      timestamp:     cs.created_at,
      icon:          new_device ? "ri-alert-line" : "ri-login-box-line",
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
                     "Eleksyon #{oak.bonvote_election&.election_date&.year}"
    new(
      kind:          :oath,
      source_record: oak,
      timestamp:     oak.accepted_at,
      icon:          "ri-quill-pen-line",
      title:         "Ou siyen Sèman Vòt la pou #{election_label}",
      subtitle:      "Vèsyon #{oak.oath_version} · Anrejistre pou CEP",
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
    return "via #{src.sub('partner:', '').titleize}" if src.start_with?("partner:")
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

  def self.consent_icon_for(status)
    case status
    when "approved" then "ri-shield-check-line"
    when "revoked"  then "ri-forbid-2-line"
    when "pending"  then "ri-time-line"
    when "expired"  then "ri-history-line"
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
