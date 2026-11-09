# frozen_string_literal: true

# A browser a citizen has signed in from. See Citizens::DeviceRecognition.
class KnownDevice < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: { scope: :user_id }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  # Friendly "Chrome on Android" label for the alert email. Intentionally rough.
  def label
    ua = user_agent.to_s
    browser =
      case ua
      when /Edg\//i              then "Edge"
      when /OPR\/|Opera/i        then "Opera"
      when /SamsungBrowser/i     then "Samsung Internet"
      when /Chrome\/|CriOS/i     then "Chrome"
      when /Firefox\/|FxiOS/i    then "Firefox"
      when /Safari\//i           then "Safari"
      else "Unknown browser"
      end
    os =
      case ua
      when /iPhone/i             then "iPhone"
      when /iPad/i               then "iPad"
      when /Android/i            then "Android"
      when /Windows/i            then "Windows"
      when /Mac OS X|Macintosh/i then "Mac"
      when /Linux/i              then "Linux"
      end
    os ? "#{browser} on #{os}" : browser
  end

  def location
    [ city, country ].compact_blank.join(", ").presence
  end
end
