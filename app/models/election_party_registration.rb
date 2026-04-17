# frozen_string_literal: true

# Tracks party/grouping registration per Article 143 of the electoral decree.
#
# Flow: submitted → under_review → approved/rejected
# Once approved, the party can nominate candidates.
#
# Two types:
#   - "party"    → Single political party (10 required documents)
#   - "grouping" → Groupement/Regroupement of parties (11 required documents)
#
class ElectionPartyRegistration < ApplicationRecord
  belongs_to :election, class_name: "BonvoteElection"
  belongs_to :user, optional: true
  has_many :candidates, class_name: "ElectionCandidate", foreign_key: :party_registration_id, dependent: :nullify

  REGISTRATION_TYPES = %w[party grouping].freeze
  STATUSES = %w[submitted under_review approved rejected withdrawn].freeze

  validates :party_name, presence: true
  validates :party_name, uniqueness: { scope: :election_id, message: "deja enskri pou eleksyon sa a" }
  validates :representative_name, presence: true
  validates :registration_type, inclusion: { in: REGISTRATION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :rejection_reason, presence: true, if: -> { status == "rejected" }

  scope :parties,   -> { where(registration_type: "party") }
  scope :groupings, -> { where(registration_type: "grouping") }
  scope :submitted, -> { where(status: "submitted") }
  scope :under_review, -> { where(status: "under_review") }
  scope :approved,  -> { where(status: "approved") }
  scope :rejected,  -> { where(status: "rejected") }
  scope :pending_review, -> { where(status: %w[submitted under_review]) }

  # ── Document Checklist ──

  # Documents required for a single party (Article 143)
  PARTY_DOCUMENTS = [
    { field: :doc_acte_constitutif,    label: "Acte constitutif notarié du parti politique", ref: 1 },
    { field: :doc_acte_reconnaissance, label: "Acte de reconnaissance du parti politique", ref: 2 },
    { field: :doc_statuts,             label: "Statuts du parti", ref: 3 },
    { field: :doc_pv_assemblee,        label: "Procès-verbal de la plus récente assemblée générale ou congrès", ref: 4 },
    { field: :doc_acte_mandataire,     label: "Acte notarié autorisant le mandataire (si applicable)", ref: 5 },
    { field: :doc_lettre_ministere,    label: "Correspondance du Ministère de la Justice attestant l'enregistrement", ref: 6 },
    { field: :doc_sigle,               label: "Sigle du parti politique", ref: 7 },
    { field: :doc_embleme,             label: "Emblème (Logo) du parti en couleur", ref: 8 },
    { field: :doc_cin_representant,    label: "Copie couleur CIN valide du représentant officiel ou mandataire", ref: 9 },
    { field: :doc_logo_numerique,      label: "Logo en format JPEG ou PNG (numérique)", ref: 10 }
  ].freeze

  # Additional documents for groupings/regroupements
  GROUPING_DOCUMENTS = PARTY_DOCUMENTS + [
    { field: :doc_liste_partis_signataires,     label: "Liste des partis signataires d'un accord notarié", ref: 11 },
    { field: :doc_accord_embleme_unique,        label: "Accord notarié pour emblème unique du groupement", ref: 12 },
    { field: :doc_actes_reconnaissance_membres, label: "Actes de reconnaissance de chaque parti membre", ref: 13 }
  ].freeze

  def required_documents
    registration_type == "grouping" ? GROUPING_DOCUMENTS : PARTY_DOCUMENTS
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

  # ── Status Workflow ──

  def start_review!
    return false unless status == "submitted"
    update!(status: "under_review")
  end

  def approve!(reviewer:)
    return false unless status.in?(%w[submitted under_review])
    update!(
      status: "approved",
      reviewed_by: reviewer,
      approved_at: Time.current,
      reviewed_at: Time.current
    )
  end

  def reject!(reviewer:, reason:)
    return false unless status.in?(%w[submitted under_review])
    update!(
      status: "rejected",
      reviewed_by: reviewer,
      rejection_reason: reason,
      rejected_at: Time.current,
      reviewed_at: Time.current
    )
  end

  def can_nominate_candidates?
    status == "approved"
  end

  # ── Display ──

  def display_name
    party_acronym.present? ? "#{party_name} (#{party_acronym})" : party_name
  end

  def type_label
    registration_type == "grouping" ? "Groupement/Regroupement" : "Parti Politique"
  end

  def status_label
    {
      "submitted"    => "Soumèt",
      "under_review" => "Anba Revizyon",
      "approved"     => "Apwouve",
      "rejected"     => "Rejte",
      "withdrawn"    => "Retire"
    }[status] || status&.titleize
  end

  def status_color
    {
      "submitted"    => "info",
      "under_review" => "warning",
      "approved"     => "success",
      "rejected"     => "danger",
      "withdrawn"    => "dark"
    }[status] || "secondary"
  end

  def self.stats_for(election)
    regs = where(election: election)
    {
      total: regs.count,
      parties: regs.parties.count,
      groupings: regs.groupings.count,
      submitted: regs.submitted.count,
      under_review: regs.under_review.count,
      approved: regs.approved.count,
      rejected: regs.rejected.count
    }
  end
end
