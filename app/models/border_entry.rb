# frozen_string_literal: true

class BorderEntry < ApplicationRecord
  belongs_to :officer
  belongs_to :visitor_submission
  belongs_to :partner, optional: true

  enum :entry_mode, { air: 0, sea: 1, land: 2 }

  validates :port_of_entry, :entry_mode, :entered_at, presence: true

  before_validation :assign_unit_code_from_entry_mode
  before_create     :cache_officer_metadata

  scope :entered, -> { where.not(entered_at: nil) }
  scope :exited,  -> { where.not(exited_at: nil) }

  # --- Core Helpers ---
  def active_stay?
    exited_at.nil? && (entered_at >= 90.days.ago)
  end

  def exit!
    update!(exited_at: Time.current)
  end

  private

  # Automatically tag entry unit (e.g., POLAER, POLIFRONT, BIM)
  def assign_unit_code_from_entry_mode
    self.unit_code ||= OfficerConstants::ENTRY_MODE_UNITS[entry_mode.to_sym]
  end

  # Cache officer info for quick analytics and redundancy
  def cache_officer_metadata
    self.officer_badge_id   = officer.badge_id
    self.officer_unit_name  = officer.unit_name
    self.partner_id         ||= officer.partner_id
  end
end
