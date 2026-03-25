class FailedBonidLookup < ApplicationRecord
  belongs_to :officer, optional: true
  validates :reason, presence: true
  validates :bonid, presence: true, allow_blank: true
end
