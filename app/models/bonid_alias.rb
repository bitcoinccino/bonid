# frozen_string_literal: true

# app/models/bonid_alias.rb
#
# Tracks historical BonID values when a citizen's BonID changes
# (e.g. name change causes prefix to change: JM → VP).
#
# This allows the Identity API to resolve old BonIDs to the current one,
# so partners who stored the old BonID can still look up the citizen.
#
# Supports alias chains: if a citizen changes their name twice
# (JM → VP → AB), querying "JM" resolves to "AB" by following the chain.
#
class BonidAlias < ApplicationRecord
  belongs_to :user

  validates :old_bonid, presence: true, uniqueness: true
  validates :new_bonid, presence: true
  validates :user_id, presence: true

  # Resolve an old BonID to the current one by following the alias chain.
  # Returns the current BonID if the input is an alias, or nil if not an alias.
  #
  # @param bonid [String] the BonID to look up
  # @return [String, nil] the current BonID, or nil if input is not an alias
  def self.resolve(bonid)
    seen = Set.new
    current = bonid

    loop do
      record = find_by(old_bonid: current)
      break unless record
      break if seen.include?(record.new_bonid) # prevent infinite loops
      seen.add(current)
      current = record.new_bonid
    end

    current == bonid ? nil : current
  end
end
