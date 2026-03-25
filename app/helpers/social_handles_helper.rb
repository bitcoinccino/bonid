module SocialHandlesHelper
  # Returns the correct Remix Icon class for a given platform
  def platform_icon(platform)
    {
      "twitter"   => "ri-twitter-x-line",
      "x"         => "ri-twitter-x-line",
      "facebook"  => "ri-facebook-circle-line",
      "instagram" => "ri-instagram-line",
      "linkedin"  => "ri-linkedin-box-line",
      "tiktok"    => "ri-tiktok-line",
      "github"    => "ri-github-line",
      "youtube"   => "ri-youtube-line",
      "snapchat"  => "ri-snapchat-line",
      "reddit"    => "ri-reddit-line",
      "threads"   => "ri-at-line",
      "bluesky"   => "ri-cloud-line",
      "mastodon"  => "ri-bubble-chart-line",
      "medium"    => "ri-medium-line",
      "pinterest" => "ri-pinterest-line",
      "discord"   => "ri-discord-line",
      "telegram"  => "ri-telegram-line",
      "whatsapp"  => "ri-whatsapp-line"
    }[platform.to_s.downcase] || "ri-share-line"
  end
end
