# frozen_string_literal: true

# A candidate running for a position in a specific constituency.
#
# Registration per Décret Électoral (1er Décembre 2025), Articles 180-181.
#
# Flow: draft → submitted → under_review → approved/rejected
# Once approved, status becomes "active" and the candidate appears on ballots.
#
# Candidacy types:
#   - "party"       → Nominated by an approved ElectionPartyRegistration
#   - "grouping"    → Nominated by an approved party grouping
#   - "independent" → Must provide 2% elector support petition
#
class ElectionCandidate < ApplicationRecord
  belongs_to :election, class_name: "BonvoteElection"
  belongs_to :election_constituency
  belongs_to :party_registration, class_name: "ElectionPartyRegistration", optional: true
  belongs_to :user, optional: true
  belongs_to :approved_by, class_name: "AdminUser", optional: true
  belongs_to :rejected_by, class_name: "AdminUser", optional: true

  has_many :endorsements, class_name: "ElectionCandidateEndorsement", dependent: :destroy

  # ============================================================
  # CONSTANTS
  # ============================================================
  STATUSES = %w[active withdrawn disqualified].freeze
  # Article 192-195: `preliminary_listed` is the 48-hour contestation window
  # between CEP's internal approval and the liste définitive.
  REGISTRATION_STATUSES = %w[draft submitted under_review preliminary_listed approved rejected withdrawn].freeze
  # Decree Article 192: "Dans les quarante-huit (48) heures de l'affichage
  # des listes préliminaires…"
  CONTESTATION_WINDOW = 48.hours
  POSITIONS = %w[president senator deputy].freeze
  CANDIDACY_TYPES = %w[party grouping independent].freeze

  # Registration fees per Décret Électoral Article 185 (in Gourdes)
  REGISTRATION_FEES = {
    "president" => 800_000,
    "senator"   => 120_000,
    "deputy"    => 60_000
  }.freeze

  # Article 185 — discount structure:
  #   - Women are exempt entirely ("Les candidates ne paient pas de frais
  #     d'inscription"), driven off the `sex` column.
  #   - Doctorate: 50% reduction.
  #   - Master's: 30% reduction.
  # Degree-based reductions do not stack; the women's exemption supersedes.
  EDUCATION_LEVELS = %w[masters doctorate].freeze
  DEGREE_REDUCTION_PCT = { "doctorate" => 50, "masters" => 30 }.freeze

  # Required documents per Article 181
  REQUIRED_DOCUMENTS = [
    { field: :doc_cin_oni,                label: "CIN oswa Sètifika ONI", ref: 1, all: true },
    { field: :doc_birth_certificate,      label: "Ak nesans / Ekstrè achiv", ref: 2, all: true },
    { field: :doc_casier_judiciaire,      label: "Ekstrè kazye jidisyè (DCPJ)", ref: 3, all: true },
    { field: :doc_dgi_receipt,            label: "Kitans DGI (frè enskripsyon peye)", ref: 4, all: true },
    { field: :doc_residence_attestation,  label: "Atestasyon rezidans", ref: 5, all: true },
    { field: :doc_passport_photos,        label: "4 foto idantite resan (papye + elektwonik)", ref: 6, all: true },
    { field: :doc_profession_proof,       label: "Atestasyon pwofesyon / aktivite", ref: 7, all: true },
    { field: :doc_property_proof,         label: "Atestasyon pwopriyete imobilye", ref: 8, positions: %w[president senator] },
    { field: :doc_immigration_cert,       label: "Sètifika imigrasyon", ref: 9, conditional: true },
    { field: :doc_discharge,              label: "Dechaj (si ansyen fonksyonè leta)", ref: 10, conditional: true },
    { field: :doc_party_mandate,          label: "Atestasyon pati politik", ref: 11, candidacy_types: %w[party grouping] },
    { field: :doc_support_petition,       label: "Petisyon 2% elektè (endepandan)", ref: 12, candidacy_types: %w[independent] }
  ].freeze

  # ============================================================
  # VALIDATIONS
  # ============================================================
  validates :full_name, presence: true
  validates :position, presence: true, inclusion: { in: POSITIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :registration_status, inclusion: { in: REGISTRATION_STATUSES }, allow_nil: true
  validates :candidacy_type, inclusion: { in: CANDIDACY_TYPES }, allow_nil: true
  validates :bonid, uniqueness: { scope: :election_id, message: "deja enskri pou eleksyon sa a" }, allow_blank: true
  validates :recepisse_number, uniqueness: true, allow_blank: true
  validates :platform_statement, presence: true, on: :submission
  validates :rejection_reason, presence: true, if: -> { registration_status == "rejected" }
  validates :sex, inclusion: { in: %w[M F] }, allow_blank: true
  validates :education_level, inclusion: { in: EDUCATION_LEVELS }, allow_blank: true

  # ============================================================
  # SCOPES
  # ============================================================
  scope :active,     -> { where(status: "active") }
  scope :presidents, -> { where(position: "president") }
  scope :senators,   -> { where(position: "senator") }
  scope :deputies,   -> { where(position: "deputy") }
  scope :for_department, ->(code) { where(department_code: code) }
  scope :for_commune, ->(id) { where(commune_id: id) }
  scope :winners,    -> { where(winner: true) }
  scope :runoff_qualified, -> { where(qualified_runoff: true) }
  scope :independents, -> { where(candidacy_type: "independent") }
  scope :party_candidates, -> { where(candidacy_type: %w[party grouping]) }

  # Registration scopes
  scope :draft,        -> { where(registration_status: "draft") }
  scope :submitted,    -> { where(registration_status: "submitted") }
  scope :under_review, -> { where(registration_status: "under_review") }
  scope :preliminary_listed, -> { where(registration_status: "preliminary_listed") }
  scope :approved,     -> { where(registration_status: "approved") }
  scope :rejected,     -> { where(registration_status: "rejected") }
  scope :pending_review, -> { where(registration_status: %w[submitted under_review]) }
  scope :on_ballot,    -> { where(registration_status: %w[preliminary_listed approved]) }

  # ============================================================
  # REGISTRATION WORKFLOW
  # ============================================================

  def submit!
    return false unless registration_status.in?([ nil, "draft" ])

    self.registration_fee_gourdes = calculate_fee
    self.recepisse_number = generate_recepisse_number

    update!(
      registration_status: "submitted",
      submitted_at: Time.current,
      recepisse_issued_at: Time.current
    )
  end

  def start_review!
    return false unless registration_status == "submitted"
    update!(registration_status: "under_review")
  end

  # Article 192: CEP posts the liste préliminaire. Candidates move to
  # `preliminary_listed` and the 48-hour contestation window opens.
  # Independent candidates must have hit the 2% petition threshold
  # (Article 181.15) before CEP can publish them — the controller surfaces
  # a clear error message when this fails.
  def publish_to_preliminary!(admin:)
    return false unless registration_status.in?(%w[submitted under_review])
    return false if independent? && !petition_satisfied?

    update!(
      registration_status: "preliminary_listed",
      status: "active", # appears on public preliminary roster
      preliminary_listed_at: Time.current,
      approved_at: Time.current,
      approved_by: admin
    )
  end

  # Article 195: after the contestation window has closed and any upheld
  # objections have rejected the relevant candidates, CEP publishes the
  # liste définitive. `approve!` is the final-list promotion.
  def approve!(admin:)
    return false unless registration_status.in?(%w[preliminary_listed submitted under_review])

    now = Time.current
    update!(
      registration_status: "approved",
      status: "active",
      approved_at: approved_at || now,
      approved_by: approved_by || admin,
      final_listed_at: now
    )
  end

  # Reject can fire from any pre-final state — used both for CEP's own
  # review rejection and for contestation-upheld removal from the
  # preliminary list.
  def reject!(admin:, reason:)
    return false unless registration_status.in?(%w[submitted under_review preliminary_listed])

    update!(
      registration_status: "rejected",
      status: "disqualified",
      rejection_reason: reason,
      rejected_at: Time.current,
      rejected_by: admin
    )
  end

  # True while the candidate is still inside the 48-hour window during
  # which any voter can file a contestation (Article 192).
  def contestation_window_open?
    return false unless registration_status == "preliminary_listed"
    return false if preliminary_listed_at.blank?
    Time.current < preliminary_listed_at + CONTESTATION_WINDOW
  end

  def contestation_window_closes_at
    return nil if preliminary_listed_at.blank?
    preliminary_listed_at + CONTESTATION_WINDOW
  end

  def withdraw!
    update!(
      registration_status: "withdrawn",
      status: "withdrawn"
    )
  end

  # ============================================================
  # DOCUMENT CHECKLIST
  # ============================================================

  def required_documents
    REQUIRED_DOCUMENTS.select do |doc|
      next true if doc[:all]
      next true if doc[:positions]&.include?(position)
      next true if doc[:candidacy_types]&.include?(candidacy_type)
      false
    end
  end

  def documents_submitted_count
    required_documents.count { |doc| send(doc[:field]) }
  end

  def documents_total_count
    required_documents.size
  end

  def documents_complete?
    required_documents.all? { |doc| send(doc[:field]) }
  end

  def documents_progress_percentage
    return 0 if documents_total_count.zero?
    (documents_submitted_count.to_f / documents_total_count * 100).round
  end

  # ============================================================
  # FEE CALCULATION
  # ============================================================

  # Article 185. Women → exempt. Else: degree reduction (doctorate 50%,
  # master's 30%), or full fee. Returns an Integer in gourdes.
  def calculate_fee
    base = REGISTRATION_FEES[position] || 0
    return 0 if sex == "F"

    reduction = DEGREE_REDUCTION_PCT[education_level] || 0
    base * (100 - reduction) / 100
  end

  # Label used in the registration wizard + recepisse. "Egzante" covers the
  # women's exemption since the fee is zero, not merely reduced.
  def fee_label
    fee = calculate_fee
    prefix = fee.zero? ? "Egzante — " : ""
    "#{prefix}#{number_with_delimiter(fee)} G"
  rescue
    "#{calculate_fee} G"
  end

  # Human-readable reason when a discount or exemption applies. Nil when the
  # candidate pays full price.
  def fee_discount_reason
    return "Fanm — egzante (Atik 185)" if sex == "F"
    return "Doktora — rediksyon 50% (Atik 185)" if education_level == "doctorate"
    return "Mastè — rediksyon 30% (Atik 185)" if education_level == "masters"
    nil
  end

  # ============================================================
  # REGISTRATION HELPERS
  # ============================================================

  def registration_pending?
    registration_status.in?(%w[submitted under_review])
  end

  def registration_complete?
    registration_status.in?(%w[approved rejected withdrawn])
  end

  def independent?
    candidacy_type == "independent"
  end

  def party_candidate?
    candidacy_type.in?(%w[party grouping])
  end

  # ============================================================
  # Article 181.15 — 2% support petition (independent only)
  # ============================================================
  SUPPORT_PETITION_PCT = 2

  # Size of the electorate this candidate must petition. The decree says
  # "électeurs inscrits dans la circonscription" — we scope by constituency:
  # president → national roll, senator → department roll, deputy → commune roll.
  def petition_denominator
    records = VoterEligibilityRecord.where(bonvote_election_id: election_id)
    case position
    when "president"
      records.count
    when "senator"
      dept = residence_department.presence || department_code.presence
      dept.present? ? records.where(department_code: dept).count : records.count
    when "deputy"
      if commune_id.present?
        records.where(commune_id: commune_id).count
      else
        records.count
      end
    else
      records.count
    end
  end

  # Integer threshold rounded up — 2% of 10,000 is 200, 2% of 10,001 is 201.
  def petition_threshold
    ((petition_denominator * SUPPORT_PETITION_PCT).to_f / 100).ceil
  end

  def endorsement_count
    endorsements.verified.count
  end

  # Only independents need the petition; everyone else is exempt.
  def petition_satisfied?
    return true unless independent?
    endorsement_count >= petition_threshold
  end

  def petition_progress_percentage
    return 100 unless independent?
    return 0 if petition_threshold.zero?
    [ (endorsement_count.to_f / petition_threshold * 100).round, 100 ].min
  end

  def registration_status_label
    {
      "draft"               => "Bouyon",
      "submitted"           => "Soumèt",
      "under_review"        => "Anba Revizyon",
      "preliminary_listed"  => "Sou Lis Preliminè",
      "approved"            => "Apwouve (Lis Definitif)",
      "rejected"            => "Rejte",
      "withdrawn"           => "Retire"
    }[registration_status] || registration_status&.titleize
  end

  def registration_status_color
    {
      "draft"               => "secondary",
      "submitted"           => "info",
      "under_review"        => "warning",
      "preliminary_listed"  => "primary",
      "approved"            => "success",
      "rejected"            => "danger",
      "withdrawn"           => "dark"
    }[registration_status] || "secondary"
  end

  # ============================================================
  # VOTE METHODS
  # ============================================================

  def votes(round = nil)
    round ||= election.round
    round == 2 ? votes_round2 : votes_round1
  end

  def vote_percentage(round = nil)
    round ||= election.round
    vote_field = round == 2 ? :votes_round2 : :votes_round1

    total = election_constituency
              .election_candidates
              .where(status: "active")
              .sum(vote_field)

    return 0.0 if total.zero?
    (votes(round).to_f / total * 100).round(2)
  end

  def has_majority?(round = nil)
    vote_percentage(round) > 50.0
  end

  def display_name
    if party_acronym.present?
      "#{full_name} (#{party_acronym})"
    elsif party_name.present?
      "#{full_name} — #{party_name}"
    else
      full_name
    end
  end

  # Returns the best available photo URL for this candidate.
  # Priority: 1) photo_url field  2) BonID user photo (ActiveStorage)  3) nil
  def candidate_photo_url
    return photo_url if photo_url.present?
    return Rails.application.routes.url_helpers.url_for(user.photo) if user&.photo&.attached?
    nil
  rescue StandardError
    nil
  end

  # ============================================================
  # STATS
  # ============================================================

  def self.registration_stats_for(election)
    candidates = where(election: election)
    {
      total: candidates.count,
      draft: candidates.draft.count,
      submitted: candidates.submitted.count,
      under_review: candidates.under_review.count,
      preliminary_listed: candidates.preliminary_listed.count,
      approved: candidates.approved.count,
      rejected: candidates.rejected.count,
      independents: candidates.independents.count,
      party_candidates: candidates.party_candidates.count,
      by_position: {
        president: candidates.presidents.count,
        senator: candidates.senators.count,
        deputy: candidates.deputies.count
      }
    }
  end

  private

  def generate_recepisse_number
    prefix = position&.first&.upcase || "X"
    year = Time.current.year
    random = SecureRandom.hex(4).upcase
    "REC-#{year}-#{prefix}-#{random}"
  end
end
