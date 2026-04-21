# frozen_string_literal: true

# Lightweight voter registry: maps a verified BonID holder to their
# constituency and tracks eligibility + voting status.
#
# ONI manages identity — this model is just the CEP's lookup:
#   "Is this person eligible to vote, and where?"
#
class VoterEligibilityRecord < ApplicationRecord
  # ============================================================
  # ASSOCIATIONS
  # ============================================================
  belongs_to :bonvote_election
  # Optional: analog voters registered at a CEP office have no BonID and
  # therefore no user record. CIN + partner stamp identifies them instead.
  belongs_to :user, optional: true

  # Phase 2 polling-station assignment (nullable during rollout — behavior
  # change to `register_voter!` ships in a follow-up commit).
  belongs_to :polling_station, optional: true
  belongs_to :transferred_from_station,
             class_name: "PollingStation",
             optional: true

  # Cached geographic scope — set at registration, read during BV lookups
  # and transfers. Decouples voter assignment from profile updates.
  belongs_to :communal_section, optional: true

  # Audit: which partner (CEP office / consulate) registered this voter.
  # Nil for passive self-registration through the citizen app.
  belongs_to :registered_by_partner,
             class_name: "Partner",
             optional: true

  # Audit: which CEP BED/BEK registered this voter (clerk-assisted path).
  # Nil for self-service digital registration.
  belongs_to :registered_by_electoral_office,
             class_name: "ElectoralOffice",
             optional: true

  # Printable / downloadable BonID-generated receipt. Re-generated on demand
  # but cached here so a citizen who lost their download link doesn't trigger
  # a fresh Prawn render every time.
  has_one_attached :receipt_pdf

  # ============================================================
  # CONSTANTS
  # ============================================================
  STATUSES = %w[eligible ineligible suspended].freeze

  # Geographic channel — where the voter is based.
  CHANNELS = %w[domestic diaspora].freeze

  # Citizen-declared intent for how they plan to vote.
  PREFERRED_CHANNELS = %w[in_person online].freeze

  # Actual channel used when the ballot landed.
  # - in_person:           paper ballot at a domestic BV
  # - online:              in-app ballot (requires election.allows_online_voting)
  # - consulate_in_person: paper ballot at a diaspora polling center
  VOTED_CHANNELS = %w[in_person online consulate_in_person].freeze

  # Origin of the enrollment record.
  # - digital: citizen self-registered online via BonID (primary path)
  # - clerk:   a clerk at a BonID-equipped desk registered the citizen in
  #            BonID on their behalf (walk-in at a consulate, BED/BEK with
  #            BonID terminals, partner office, etc.)
  SOURCES = %w[digital clerk].freeze

  # Raised by register_digital_voter! when the active election has not
  # enabled the self-service digital enrollment flow. Controllers rescue
  # this to fall back to the clerk-assisted messaging.
  class DigitalEnrollmentNotAllowedError < StandardError; end

  INELIGIBILITY_REASONS = {
    "underage"          => "Mwens ke 18 an",
    "no_cin"            => "Pa gen CIN verifye",
    "expired_id"        => "Pyès idantite ekspire",
    "non_haitian"       => "Pa sitwayen ayisyen",
    "suspended"         => "Dwa sivil sispann",
    "duplicate"         => "Deja anrejistre"
  }.freeze

  # ============================================================
  # VALIDATIONS
  # ============================================================
  # CIN is the identity anchor for every voter — BonID or not.
  # Presence is required for analog voters today; digital-path presence
  # will be enforced in the commit that rewrites register_voter!.
  validates :cin_number, presence: true, if: -> { user_id.blank? }
  validates :cin_number,
            uniqueness: { scope: :bonvote_election_id,
                          message: "deja anrejistre pou eleksyon sa a" },
            allow_nil: true

  validates :department_code, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :channel, inclusion: { in: CHANNELS }, allow_blank: true
  # BonID remains unique when present, but is now optional (analog voters).
  validates :bonid,
            uniqueness: { scope: :bonvote_election_id,
                          message: "deja anrejistre pou eleksyon sa a" },
            allow_nil: true
  validates :ineligibility_reason, inclusion: { in: INELIGIBILITY_REASONS.keys }, allow_nil: true
  validates :constituency_name, presence: true, if: :eligible?

  validates :preferred_channel, inclusion: { in: PREFERRED_CHANNELS }
  validates :voted_channel, inclusion: { in: VOTED_CHANNELS }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }

  # Analog voters (no BonID, no user_id) must be attributable to the
  # CEP office or consulate that registered them — no self-service path.
  validate :partner_required_for_analog_voter

  # ============================================================
  # SCOPES
  # ============================================================
  scope :eligible,    -> { where(status: "eligible") }
  scope :ineligible,  -> { where(status: "ineligible") }
  scope :voted,       -> { where(has_voted: true) }
  scope :not_voted,   -> { where(has_voted: false) }
  scope :domestic,    -> { where(channel: "domestic") }
  scope :diaspora,    -> { where(channel: "diaspora") }
  scope :for_department, ->(code) { where(department_code: code) }

  # ============================================================
  # CLASS METHODS
  # ============================================================

  # Primary registration entry point — handles both the digital and the
  # analog paths, plus link-back (attaches a BonID-verified user to a
  # previously clerk-created analog record for the same CIN/election).
  #
  #   # Digital, self-registered via the citizen app:
  #   register_voter!(election: e, user: u)
  #
  #   # Digital, registered at a CEP or consulate desk:
  #   register_voter!(election: e, user: u, registered_by: partner,
  #                   preferred_channel: "online")
  #
  #   # Analog (no BonID) — clerk typed the CIN and geography:
  #   register_voter!(
  #     election: e,
  #     cin_number: "12345-...",
  #     registered_by: partner,
  #     department_code: "OU",
  #     commune_id: commune.id,
  #     communal_section_id: section.id
  #   )
  def self.register_voter!(election:,
                           user: nil,
                           cin_number: nil,
                           registered_by: nil,
                           preferred_channel: nil,
                           department_code: nil,
                           commune_id: nil,
                           communal_section_id: nil,
                           diplomatic_mission_id: nil)
    if user.present?
      register_digital_voter!(
        election: election,
        user: user,
        registered_by: registered_by,
        preferred_channel: preferred_channel
      )
    else
      register_analog_voter!(
        election: election,
        cin_number: cin_number,
        registered_by: registered_by,
        preferred_channel: preferred_channel,
        department_code: department_code,
        commune_id: commune_id,
        communal_section_id: communal_section_id,
        diplomatic_mission_id: diplomatic_mission_id
      )
    end
  end

  # ── Digital path: a verified BonID holder is being registered ────
  # (self-service, or CEP/consulate desk with a BonID-verified citizen).
  #
  # Gated by `election.allows_digital_enrollment` when called on the
  # self-service path (no `registered_by` partner/office). Clerk-assisted
  # calls bypass the gate — a CEP employee is physically present and
  # responsible for the record, so the CEP policy knob shouldn't block them.
  def self.register_digital_voter!(election:, user:, registered_by: nil,
                                   registered_by_office: nil,
                                   preferred_channel: nil)
    if registered_by.nil? && registered_by_office.nil? &&
       election.respond_to?(:allows_digital_enrollment?) &&
       !election.allows_digital_enrollment?
      raise DigitalEnrollmentNotAllowedError,
            "Eleksyon sa a pa aksepte enskripsyon anliy pou lemoman."
    end

    record = find_or_link_back_record_for_user(election, user)
    return record if record.persisted? && record.eligible? && record.polling_station_id.present?

    # Attach identity (link-back promotes an analog record to digital)
    record.user        = user
    record.bonid       = user.bonid       if user.bonid.present?
    record.cin_number  = user.cin_unique_id if user.cin_unique_id.present?

    # Source: clerk-assisted when an electoral office stamp is present,
    # otherwise digital (self-service). `registered_by` partner stamp is
    # the legacy analog path — preserved as "clerk" too.
    record.source = (registered_by_office || registered_by) ? "clerk" : "digital"

    apply_digital_eligibility!(record, election, user)
    apply_registration_metadata!(record, registered_by, preferred_channel)
    record.registered_by_electoral_office = registered_by_office if registered_by_office

    record.save!
    assign_polling_station!(record)
    record.stamp_bonvote_signature!
    record.deliver_receipt_sms!
    record.deliver_receipt_email!

    record
  end

  # ── Analog path: a walk-in voter with no BonID is being registered ─
  # Clerk verifies CIN on paper and types the geographic scope. The
  # registered_by partner stamp is mandatory — no self-service here.
  def self.register_analog_voter!(election:, cin_number:, registered_by:,
                                  preferred_channel: nil,
                                  department_code: nil,
                                  commune_id: nil,
                                  communal_section_id: nil,
                                  diplomatic_mission_id: nil)
    raise ArgumentError, "cin_number is required for analog registration"    if cin_number.blank?
    raise ArgumentError, "registered_by is required for analog registration" if registered_by.nil?
    raise ArgumentError, "department_code is required for analog registration" if department_code.blank?

    record = find_or_initialize_by(bonvote_election: election, cin_number: cin_number)
    return record if record.persisted? && record.eligible? && record.polling_station_id.present?

    is_diaspora = diplomatic_mission_id.present?

    # Clerk-verified eligibility — the partner already confirmed the CIN,
    # age, and residency in person. We trust that judgment.
    record.assign_attributes(
      status: "eligible",
      department_code: department_code,
      commune_id: commune_id,
      communal_section_id: communal_section_id,
      diplomatic_mission_id: diplomatic_mission_id,
      channel: is_diaspora ? "diaspora" : "domestic",
      verified_at: Time.current
    )
    record.constituency_name = resolve_constituency(election, record)
    apply_registration_metadata!(record, registered_by, preferred_channel)

    record.save!
    assign_polling_station!(record)
    record.stamp_bonvote_signature!
    record.deliver_receipt_sms!
    record.deliver_receipt_email!

    record
  end

  # Assigns the voter to the first available BV in their section
  # (domestic) or supervising mission (diaspora). Safe for concurrent
  # callers: FOR UPDATE SKIP LOCKED guarantees two clerks registering
  # voters in the same section simultaneously land on different BVs.
  # Returns the PollingStation or nil (graceful fallback — voter is
  # still registered, just without a BV; ops can rerun later).
  def self.assign_polling_station!(record)
    return nil unless record.eligible?
    return record.polling_station if record.polling_station_id.present?

    scope = polling_station_scope(record)
    return nil if scope.nil?

    station = nil
    transaction do
      station = scope.lock("FOR UPDATE SKIP LOCKED").first
      next unless station

      new_count = station.registered_count + 1
      station.update!(
        registered_count: new_count,
        status: new_count >= station.capacity ? "full" : "open"
      )
      record.update!(
        polling_station_id: station.id,
        assigned_at: Time.current
      )
    end

    station
  end

  # Bulk import from all verified BonID users
  def self.build_electoral_list!(election:)
    User.where.not(bonid: [ nil, "" ])
        .joins(:identity_submissions)
        .where(identity_submissions: { status: :approved })
        .distinct
        .find_each do |user|
      register_voter!(election: election, user: user)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "Voter registration skipped for user #{user.id}: #{e.message}"
    end
  end

  # Lookup: is this BonID eligible for this election?
  def self.check_eligibility(election:, bonid:)
    find_by(bonvote_election: election, bonid: bonid)
  end

  # ============================================================
  # INSTANCE METHODS
  # ============================================================
  def eligible?
    status == "eligible"
  end

  def domestic?
    channel == "domestic"
  end

  def diaspora?
    channel == "diaspora"
  end

  def mark_voted!
    update!(has_voted: true, voted_at: Time.current)
  end

  # Atomic vote commit — the single chokepoint for every channel.
  # Pessimistic lock prevents double-voting across in-person + online races:
  # if a clerk's tablet and the citizen's phone hit this method at the same
  # moment, only the first transaction wins.
  def cast_vote!(channel:)
    raise ArgumentError, "invalid channel" unless VOTED_CHANNELS.include?(channel)

    self.class.transaction do
      voter = self.class.lock.find(id)
      raise AlreadyVotedError, "deja vote" if voter.has_voted?

      voter.update!(
        has_voted: true,
        voted_at: Time.current,
        voted_channel: channel
      )
      voter
    end
  end

  # Raised by cast_vote! when a second channel tries to commit a vote
  # for a voter who has already voted. Callers (ballot controllers,
  # clerk tablets) rescue this to show "deja vote" to the user.
  class AlreadyVotedError < StandardError; end

  def ineligibility_label
    INELIGIBILITY_REASONS[ineligibility_reason] || ineligibility_reason
  end

  # Human-readable voter reference — e.g. BVT-2026-K9F2-HQXR.
  #
  # This is the BonID-issued credential that confirms the citizen is
  # registered to vote. The authoritative artifact is the BonVote-signed
  # attestation stored in `bonvote_signature`. The `BVT-` prefix
  # (Biwo Vòt Tikèt) reads as BonID's own reference, not a government ID.
  #
  # Threat model:
  #   - Must NOT be enumerable (a neighbor shouldn't be able to guess mine).
  #   - Must NOT leak enrollment order or total voter count.
  #   - Must be deterministic so a citizen who loses the receipt sees the
  #     same number when they come back to the portal.
  #   - Must be re-derivable server-side without a DB migration.
  #
  # Construction:
  #   HMAC-SHA256(secret_for_election, "voter:<user_id>:<election_id>:<id>")
  #     → first 5 bytes (40 bits)
  #     → encoded as 8 chars of Crockford base32 (no I, L, O, U — safe to
  #       hand-write or read over the phone)
  #     → grouped as XXXX-XXXX for readability.
  #
  # The per-election secret (credentials.dig(:election, :voter_ref_secrets,
  # <election_id>)) means references can't be correlated across cycles.
  # If no per-election secret is set, we fall back to secret_key_base so
  # development and first-run production still produce stable refs.
  def voter_reference
    year = bonvote_election&.election_date&.year ||
           bonvote_election&.created_at&.year ||
           Time.current.year
    token = reference_token
    "BVT-#{year}-#{token[0, 4]}-#{token[4, 4]}"
  end

  # Look up a record by its derived voter_reference. Because the reference
  # is an HMAC of (user_id, election_id, record_id) — not a stored column —
  # we can't index a direct WHERE. Instead, parse the year out of the ref,
  # narrow candidates to elections from that year, and recompute references
  # to find the match. Cheap at current scale; revisit with a denormalized
  # indexed column when we approach production voter counts.
  def self.find_by_voter_reference(ref)
    return nil if ref.blank?

    normalized = ref.to_s.upcase.gsub(/\s+/, "")
    m = normalized.match(/\ABVT-(\d{4})-([0-9A-Z]{4})-([0-9A-Z]{4})\z/)
    return nil unless m

    year   = m[1].to_i
    target = "BVT-#{year}-#{m[2]}-#{m[3]}"

    election_ids = BonvoteElection
                     .where("EXTRACT(YEAR FROM election_date) = ? OR EXTRACT(YEAR FROM created_at) = ?", year, year)
                     .pluck(:id)
    return nil if election_ids.empty?

    where(bonvote_election_id: election_ids).find_each do |rec|
      return rec if rec.voter_reference == target
    end
    nil
  end

  # Compact payload embedded in the receipt QR code. Poll workers scan this
  # at the polling station to verify registration offline — the QR carries
  # enough to look up + confirm without a network round-trip, and the
  # optional `bonvote_signature` (when populated by BonvoteSigningService)
  # lets a verification tablet confirm authenticity cryptographically.
  #
  # `kid` (key identifier) lets a verifier pick the right public key when a
  # rotation has happened: archived keys live in the BonvoteKeyRegistry and
  # are looked up by exactly this kid. Without kid in the payload, an old
  # receipt becomes unverifiable the moment a key rotates.
  #
  # Intentionally short so the QR stays dense on cheap thermal prints.
  def receipt_qr_payload
    {
      v:   1,                       # payload version
      ref: voter_reference,
      bon: bonid_short,             # last 6 chars — unique without leaking DOB/sex/dept
      e:   bonvote_election_id,
      bv:  polling_station&.bv_number,
      c:   polling_station&.polling_center&.name,
      kid: bonvote_election && ::Election::BonvoteKeyRegistry.current(bonvote_election)&.key_id,
      s:   bonvote_signature.presence
    }.compact
  end

  # Last 6 alphanumeric characters of the BonID — enough to disambiguate at
  # a polling station, with zero demographic leakage. The BonID prefix
  # encodes year-of-birth, sex, and department code; surfacing it on a
  # public receipt would broadcast PII to anyone who scans the QR.
  def bonid_short
    bonid.to_s.tr("-", "").last(6)
  end

  # URL embedded in the receipt QR. Scanning the QR with a phone camera
  # opens the BonID verifier directly with the payload pre-filled — no
  # manual paste step. The verify page decodes `?d=`, recomputes the
  # canonical signing payload, fetches the election's public key from the
  # registry, and shows pass/fail.
  def receipt_qr_url(host: nil, protocol: nil)
    payload = receipt_qr_payload.to_json
    encoded = Base64.urlsafe_encode64(payload, padding: false)
    base    = host.presence ||
              Rails.application.routes.default_url_options[:host].presence ||
              "bonid.ht"
    scheme  = protocol.presence ||
              Rails.application.routes.default_url_options[:protocol].presence ||
              (Rails.env.production? ? "https" : "http")
    "#{scheme}://#{base}/election/verify-receipt?d=#{encoded}"
  end

  # Fire-and-forget email receipt. Sends the citizen a PDF attachment of
  # their voter registration receipt so they can print at a copy shop, save
  # it outside BonID, or forward to a family member. Silent no-op when no
  # email is on file.
  def deliver_receipt_email!
    return if user&.email.blank?

    ::Election::VoterReceiptMailer.registration_confirmation(id).deliver_later
  end

  # Fire-and-forget SMS receipt. The citizen gets their voter_reference
  # and assigned BV (when known) so the credential survives losing the
  # app / clearing the browser — usable on election day even without
  # smartphone access. Silent no-op when no phone is on file; the job
  # itself normalizes Haitian local numbers to E.164.
  def deliver_receipt_sms!
    phone = user&.phone
    return if phone.blank?

    bv = polling_station&.bv_number
    center = polling_station&.polling_center&.name
    bv_line = bv ? " BV ##{bv}#{center ? " — #{center}" : ''}." : ""
    body = "BonVote: Ou enskri pou eleksyon an. Referans ou: " \
           "#{voter_reference}.#{bv_line} Pa pataje."

    SendSmsJob.perform_later(phone, body, context: "voter_receipt")
  end

  # Signs the receipt payload with the election's Ed25519 key and stamps
  # the result on the record. Safe to call multiple times — idempotent on
  # the payload (canonical JSON + stable voter_reference), so re-stamping
  # after a BV reassignment simply refreshes the signature.
  #
  # The signing authority is BonVote. BonVote follows CEP's protocol; the
  # signature attests "BonVote issued this receipt according to CEP's
  # protocol" — not "CEP issued this receipt."
  #
  # If signing keys aren't configured for this election yet, we log and
  # skip — the receipt still renders, just without the cryptographic
  # attestation that lets a tablet verify it offline.
  def stamp_bonvote_signature!
    # Reload so we're checking persisted state, not whatever the caller had
    # in memory after a chain of assign_attributes / callbacks / class-level
    # updates. Without this, `eligible?` can read a stale in-memory status
    # and silently skip signing on successful enrollments.
    reload if persisted?

    unless bonvote_election
      Rails.logger.warn "[stamp_bonvote_signature!] skipped: no bonvote_election on record ##{id}"
      return
    end
    unless eligible?
      Rails.logger.warn "[stamp_bonvote_signature!] skipped: status=#{status.inspect} (not 'eligible') on record ##{id}"
      return
    end

    # Mirror the credential key into the election row BEFORE computing the
    # payload. `receipt_qr_payload` reads `BonvoteKeyRegistry.current`,
    # which only returns a Key (and therefore a `kid:` field) once
    # `bonvote_public_key` has been synced from credentials. Without this
    # call the first signature would be over a payload WITHOUT `kid`,
    # while later verifications — run after `sync!` populates the column —
    # would rebuild the payload WITH `kid` and fail the signature check.
    ::Election::BonvoteKeyRegistry.sync!(bonvote_election)

    # Strip the signature field itself before signing so the payload is
    # stable regardless of any prior attestation (idempotency + re-stamp
    # support after BV moves).
    payload = receipt_qr_payload.except(:s)
    sig = ::Election::BonvoteSigningService.sign(election: bonvote_election, payload: payload)

    update_columns(
      bonvote_signature: sig,
      bonvote_signed_at: Time.current,
      receipt_generated_at: receipt_generated_at || Time.current
    )
    sig
  rescue ::Election::BonvoteSigningService::NotConfiguredError => e
    Rails.logger.info(
      "[VoterEligibilityRecord] BonVote signing skipped for record ##{id} " \
      "election=#{bonvote_election_id} reason=#{e.message}"
    )
    nil
  rescue ::Election::BonvoteSigningService::InvalidKeyError => e
    Rails.logger.error(
      "[VoterEligibilityRecord] BonVote signing key invalid for record ##{id} " \
      "election=#{bonvote_election_id} error=#{e.message}"
    )
    nil
  end

  private

  CROCKFORD_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".freeze

  def reference_token
    payload = "voter:#{user_id}:#{bonvote_election_id}:#{id}"
    mac = OpenSSL::HMAC.digest("SHA256", reference_secret, payload)
    encode_crockford(mac.byteslice(0, 5))
  end

  def reference_secret
    per_election = Rails.application.credentials.dig(
      :election, :voter_ref_secrets, bonvote_election_id.to_s
    )
    per_election.presence ||
      Rails.application.credentials.secret_key_base.presence ||
      "bonid-voter-ref-#{Rails.env}"
  end

  # 40-bit → 8-char Crockford base32 string.
  def encode_crockford(bytes)
    num  = bytes.unpack1("H*").to_i(16)
    chars_needed = (bytes.bytesize * 8) / 5
    out = String.new(capacity: chars_needed)
    chars_needed.times do
      out.prepend(CROCKFORD_ALPHABET[num & 0x1F])
      num >>= 5
    end
    out
  end

  public

  # Display-friendly department name. `department_code` is stored as the
  # slug (e.g. "sud-est") so it can join to the Department table; the view
  # should show the proper label ("Sud-Est").
  def department_display_name
    Department.find_by(slug: department_code)&.name || department_code
  end

  # Human-readable, multi-line geographic chain for the registered card.
  # Uses the cached communal_section when present (most complete), falling
  # back through commune → department so something still renders while
  # the CEP is finishing its geography tables.
  def geographic_chain
    section = communal_section
    commune = section&.commune
    arr     = commune&.arrondissement
    dept    = arr&.department || Department.find_by(slug: department_code)

    {
      section:       section&.name,
      commune:       commune&.name,
      arrondissement: arr&.name,
      department:    dept&.name || department_code
    }
  end

  # Returns the biometric anchor for voter key derivation.
  # Falls back to BonID hash if face_id was not yet enrolled
  # (e.g. pre-Rekognition accounts), ensuring all voters can still vote.
  def biometric_anchor
    biometric_fingerprint.presence || OpenSSL::Digest::SHA256.hexdigest(bonid.to_s)
  end

  # Stats for CEP dashboard
  def self.stats_for(election)
    records = where(bonvote_election: election)
    {
      total_registered: records.count,
      eligible: records.eligible.count,
      ineligible: records.ineligible.count,
      voted: records.voted.count,
      turnout_pct: records.eligible.count.zero? ? 0 : (records.voted.count.to_f / records.eligible.count * 100).round(2),
      domestic: records.domestic.count,
      diaspora: records.diaspora.count
    }
  end

  # ============================================================
  # PRIVATE CLASS METHODS (registration internals)
  # ============================================================
  class << self
    private

    # Prefer a record already keyed to this user; otherwise link back to
    # an analog (user_id IS NULL) record for the same CIN. Only creates
    # a new row if neither exists — prevents duplicate voter identities
    # when a citizen who was clerk-registered later obtains BonID.
    def find_or_link_back_record_for_user(election, user)
      record = find_by(bonvote_election: election, user: user)

      if record.nil? && user.cin_unique_id.present?
        record = find_by(
          bonvote_election: election,
          cin_number: user.cin_unique_id,
          user_id: nil
        )
      end

      record || new(bonvote_election: election, user: user)
    end

    # Evaluates eligibility + populates geographic fields for a digital
    # (BonID-backed) voter. Mirrors the legacy logic, now also caching
    # `communal_section_id` so the assigner has what it needs.
    def apply_digital_eligibility!(record, election, user)
      submission      = user.identity_submissions.where(status: :approved).order(created_at: :desc).first
      address         = user.address
      local_dept_code = address&.department&.slug || "UNKNOWN"

      if user.bonid.blank? || submission.blank?
        record.assign_attributes(
          status: "ineligible",
          ineligibility_reason: "no_cin",
          department_code: local_dept_code
        )
        return
      end

      if user.dob.blank? || user.age < 18
        record.assign_attributes(
          status: "ineligible",
          ineligibility_reason: "underage",
          department_code: local_dept_code
        )
        return
      end

      if submission.expires_at.present? && submission.expires_at < Time.current
        record.assign_attributes(
          status: "ineligible",
          ineligibility_reason: "expired_id",
          department_code: local_dept_code
        )
        return
      end

      # Eligible — resolve constituency + geographic scope
      is_diaspora = submission.country_of_residence.present? &&
                    submission.country_of_residence != "HT"
      dept_code   = is_diaspora ? submission.country_of_residence : local_dept_code

      face_id      = submission.metadata&.dig("face_collection", "face_id")
      biometric_fp = face_id.present? ? OpenSSL::Digest::SHA256.hexdigest(face_id) : nil

      record.assign_attributes(
        status: "eligible",
        department_code: dept_code,
        commune_id: address&.commune_id,
        communal_section_id: address&.communal_section_id,
        channel: is_diaspora ? "diaspora" : "domestic",
        biometric_fingerprint: biometric_fp,
        verified_at: Time.current
      )
      record.constituency_name = resolve_constituency(election, record)
    end

    # Common post-eligibility metadata: partner audit stamp, citizen-
    # declared channel preference, and registration timestamp.
    def apply_registration_metadata!(record, registered_by, preferred_channel)
      record.registered_by_partner = registered_by if registered_by
      if preferred_channel.present? && PREFERRED_CHANNELS.include?(preferred_channel.to_s)
        record.preferred_channel = preferred_channel.to_s
      end
      record.registered_at ||= Time.current
    end

    # Constituency name is derived from the election's constituency map.
    #   - Diaspora → "Dyaspora"
    #   - Domestic → deputy constituency for the commune, falling back
    #     to the department code if no matching constituency exists yet
    def resolve_constituency(election, record)
      return "Dyaspora" if record.channel == "diaspora"

      if record.commune_id.present?
        constituency = election.election_constituencies
                               .where(position: "deputy", commune_id: record.commune_id)
                               .first
        return constituency.constituency_name if constituency
      end

      record.department_code
    end

    # Builds the AR relation the locked assigner draws from. Returns nil
    # when the voter lacks the scope anchor (no section for domestic,
    # no mission for diaspora) — in that case no BV can be assigned and
    # the voter is registered with `polling_station_id: nil` (graceful
    # fallback; ops can rerun assignment once the scope is filled in).
    def polling_station_scope(record)
      base = PollingStation.available
                           .joins(:polling_center)
                           .where(polling_centers: {
                             bonvote_election_id: record.bonvote_election_id,
                             status: "open"
                           })
                           .order("polling_centers.priority ASC, polling_stations.bv_number ASC")

      if record.diaspora? && record.diplomatic_mission_id.present?
        base.where(polling_centers: { diplomatic_mission_id: record.diplomatic_mission_id })
      elsif record.domestic? && record.communal_section_id.present?
        base.where(polling_centers: { communal_section_id: record.communal_section_id })
      end
    end
  end

  private

  # Analog voters (no BonID + no user) must always carry a partner stamp
  # so every non-digital record is attributable to a responsible office.
  def partner_required_for_analog_voter
    return if user_id.present?
    return if registered_by_partner_id.present?

    errors.add(:registered_by_partner_id,
               "required for analog voter registration")
  end
end
