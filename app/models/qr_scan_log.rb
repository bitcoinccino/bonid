class QrScanLog < ApplicationRecord
  belongs_to :qr_scan
  belongs_to :partner, optional: true

  delegate :identity_submission, to: :qr_scan
end


# #  Suggested by grok
#  # Associations
#  belongs_to :qr_scan
#  belongs_to :partner, optional: true
#  has_one :identity_submission, through: :qr_scan
#  has_one :user, through: :identity_submission

#  # Validations
#  validates :qr_scan_id, presence: true
#  validates :ip_address, format: { with: /\A(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/, allow_blank: true }

#  # Enum for status
#  enum status: { pending: "pending", success: "success", failed: "failed" }, _default: "pending"

#  # Scopes for filtering
#  scope :search, ->(query) {
#    return all unless query.present?
#    joins(:partner, qr_scan: { identity_submission: :user })
#      .where("partners.name ILIKE :query OR users.full_name ILIKE :query", query: "%#{query}%")
#  }

#  scope :by_partner, ->(partner_id) {
#    return all unless partner_id.present?
#    where(partner_id: partner_id)
#  }

#  scope :by_date_range, ->(start_date, end_date) {
#    return all unless start_date && end_date
#    where(created_at: start_date.beginning_of_day..end_date.end_of_day)
#  }

#  # CSV export
#  def self.to_csv
#    attributes = %w[created_at ip_address partner_name user_name location user_agent status]

#    CSV.generate(headers: true) do |csv|
#      csv << attributes.map(&:humanize)

#      all.each do |log|
#        csv << attributes.map do |attr|
#          case attr
#          when "created_at"
#            log.created_at.strftime("%Y-%m-%d %H:%M:%S")
#          when "partner_name"
#            log.partner&.name || "—"
#          when "user_name"
#            log.user&.full_name || "N/A"
#          when "location"
#            [log.city, log.region, log.country].compact.join(", ").presence || "N/A"
#          when "user_agent"
#            log.user_agent.to_s
#          when "status"
#            log.status&.humanize
#          else
#            log.send(attr)&.to_s.presence || "N/A"
#          end
#        end
#      end
#    end
#  end
# end