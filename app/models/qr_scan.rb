# app/models/qr_scan.rb
class QrScan < ApplicationRecord
  belongs_to :identity_submission
   belongs_to :partner 
  has_many :qr_scan_logs, dependent: :destroy
  validates :partner_id, presence: true
  before_create :set_geo_info

  private

  def set_geo_info
    return if ip_address.blank?

    begin
      geo = Geocoder.search(ip_address).first
      self.country      = geo&.country.presence || "Unknown"
      self.city         = geo&.city.presence
      self.region       = geo&.state.presence
      self.organization = geo&.data.dig("org").presence # Only works with some lookup services (e.g., ipinfo.io)
    rescue => e
      Rails.logger.warn "Geolocation lookup failed: #{e.message}"
    end
  end
end






# Suggested by grok 
# # class QrScan < ApplicationRecord
#   # Associations
#   belongs_to :identity_submission
#   belongs_to :partner, optional: true
#   has_many :qr_scan_logs, dependent: :destroy
#   has_one :user, through: :identity_submission

#   # Validations
#   validates :identity_submission_id, presence: true
#   validates :ip_address, format: { with: /\A(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/, allow_blank: true }

#   # Enum for status
#   enum :status, { pending: "pending", success: "success", failed: "failed" }, default: "pending"

#   # Callbacks
#   before_create :set_geo_info

#   # Scopes for filtering
#   scope :search, ->(query) {
#     return all unless query.present?
#     joins(:partner, identity_submission: :user)
#       .where("partners.name ILIKE :query OR users.full_name ILIKE :query", query: "%#{query}%")
#   }

#   scope :by_partner, ->(partner_id) {
#     return all unless partner_id.present?
#     where(partner_id: partner_id)
#   }

#   scope :by_date_range, ->(start_date, end_date) {
#     return all unless start_date && end_date
#     where(created_at: start_date.beginning_of_day..end_date.end_of_day)
#   }

#   # CSV export
#   def self.to_csv
#     attributes = %w[created_at ip_address partner_name user_name location user_agent status]

#     CSV.generate(headers: true) do |csv|
#       csv << attributes.map(&:humanize)

#       all.each do |scan|
#         csv << attributes.map do |attr|
#           case attr
#           when "created_at"
#             scan.created_at.strftime("%Y-%m-%d %H:%M:%S")
#           when "partner_name"
#             scan.partner&.name || "—"
#           when "user_name"
#             scan.user&.full_name || "N/A"
#           when "location"
#             [scan.city, scan.region, scan.country].compact.join(", ").presence || "N/A"
#           when "user_agent"
#             scan.user_agent.to_s
#           when "status"
#             scan.status&.humanize
#           else
#             scan.send(attr)&.to_s.presence || "N/A"
#           end
#         end
#       end
#     end
#   end

#   private

#   def set_geo_info
#     return if ip_address.blank?

#     begin
#       geo = Geocoder.search(ip_address).first
#       if geo
#         self.country      = geo.country.presence || "Unknown"
#         self.city         = geo.city.presence
#         self.region       = geo.state.presence
#         self.organization = geo.data&.dig("org").presence # Compatible with ipinfo.io or similar
#       else
#         self.country = "Unknown"
#         Rails.logger.warn "Geolocation lookup returned no data for IP: #{ip_address}"
#       end
#     rescue StandardError => e
#       self.country = "Unknown"
#       Rails.logger.warn "Geolocation lookup failed for IP: #{ip_address} - Error: #{e.message}"
#     end
#   end
# end