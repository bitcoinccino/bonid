# frozen_string_literal: true

class SocialHandle < ApplicationRecord
  belongs_to :user

  # === Constants ===
  unless const_defined?(:PLATFORMS)
    PLATFORMS = {
      twitter:        "X (Twitter)",
      facebook:       "Facebook",
      instagram:      "Instagram",
      linkedin:       "LinkedIn",
      tiktok:         "TikTok",
      github:         "GitHub",
      youtube:        "YouTube",
      snapchat:       "Snapchat",
      threads:        "Threads (Meta)",
      telegram:       "Telegram",
      discord:        "Discord",
      reddit:         "Reddit",
      medium:         "Medium",
      pinterest:      "Pinterest",
      twitch:         "Twitch",
      mastodon:       "Mastodon",
      farcaster:      "Farcaster",
      lens:           "Lens Protocol",
      bluesky:        "Bluesky",
      soundcloud:     "SoundCloud",
      spotify:        "Spotify",
      substack:       "Substack",
      dribbble:       "Dribbble",
      behance:        "Behance",
      producthunt:    "Product Hunt"
    }.freeze
  end

  unless const_defined?(:VISIBILITY_LEVELS)
    VISIBILITY_LEVELS = {
      private:        "Private",
      partners_only:  "Visible to verified partners only",
      public:         "Publicly visible"
    }.freeze
  end

  # === Enums ===
  enum :visibility, VISIBILITY_LEVELS.keys.index_with(&:to_s), prefix: true, default: :partners_only
  enum :verification_status, { unverified: 0, pending: 1, verified: 2, failed: 3 }, prefix: :verification

  # === Validations ===
  validates :platform, presence: true, inclusion: { in: PLATFORMS.keys.map(&:to_s) }
  validates :handle, presence: true,
                     format: { with: /\A[A-Za-z0-9._-]+\z/,
                               message: "can only contain letters, numbers, periods, underscores, or dashes" }
  validates :platform, uniqueness: { scope: :user_id, message: "already added for this user" }

  # === Callbacks ===
  before_validation :normalize_platform
  before_validation :normalize_handle

  # === Scopes ===
  scope :active, -> { where(active: true) }
  scope :verified, -> { where(verification_status: :verified) }
  scope :public_visible, -> { where(visibility: :public) }

  # === Instance Methods ===
  def verified?
    verification_status == "verified"
  end

  def social_url
    base = case platform
    when "twitter"   then "https://x.com/"
    when "instagram" then "https://instagram.com/"
    when "facebook"  then "https://facebook.com/"
    when "linkedin"  then "https://linkedin.com/in/"
    when "github"    then "https://github.com/"
    when "tiktok"    then "https://tiktok.com/@"
    when "youtube"   then "https://youtube.com/@"
    when "threads"   then "https://www.threads.net/@"
    when "reddit"    then "https://reddit.com/u/"
    when "telegram"  then "https://t.me/"
    when "discord"   then "https://discordapp.com/users/"
    when "farcaster" then "https://warpcast.com/"
    when "lens"      then "https://lenster.xyz/u/"
    else ""
    end
    base.present? ? "#{base}#{handle}" : handle
  end

  def display_platform
    PLATFORMS[platform.to_sym] || platform.titleize
  end

  def start_verification!
    update!(verification_status: :pending, verified_at: nil)
  end

  def mark_verified!
    update!(verification_status: :verified, verified_at: Time.current)
  end

  def mark_failed!
    update!(verification_status: :failed)
  end

  def trust_weight
    base = verified? ? 10 : 3
    weight = case platform
    when "linkedin", "github" then 10
    when "twitter", "instagram" then 8
    else 5
    end
    base + weight
  end

  private

  def normalize_platform
    self.platform = platform.to_s.strip.downcase if platform.present?
  end

  def normalize_handle
    return unless handle.present?

    self.handle = handle.strip.gsub(/^@/, "").delete(" ")
  end

  # Virtual method to generate display name on-the-fly (no column needed)
  def display_name
    "#{display_platform}: @#{handle}"
  end
end
