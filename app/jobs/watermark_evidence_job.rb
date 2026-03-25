# frozen_string_literal: true

# WatermarkEvidenceJob — applies chain-of-custody watermark to evidence photos
#
# Haiti-Optimized:
#   - Queue: :low — watermarking shouldn't block report submission on 2G
#   - Strips EXIF metadata (privacy + smaller file size)
#   - Compresses output to JPEG quality 80 (good enough for evidence)
#   - Single combine_options call (one ImageMagick subprocess, not multiple)
#
# Overlays a semi-transparent band with:
#   Line 1: Capture timestamp
#   Line 2: GPS coordinates (or "No GPS")
#   Line 3: Officer badge ID
#
# The watermarked image REPLACES the original blob. The original's
# checksum is stored in blob.metadata for forensic audit.
#
# Uses MiniMagick (ImageMagick) for text annotation.
class WatermarkEvidenceJob < ApplicationJob
  queue_as :low

  retry_on StandardError, wait: 15.seconds, attempts: 2
  discard_on ActiveJob::DeserializationError

  # @param blob_id [Integer] ActiveStorage::Blob ID
  # @param officer_badge_id [String] e.g. "PNH03456"
  # @param latitude [Float, nil]
  # @param longitude [Float, nil]
  # @param captured_at [String] ISO 8601 timestamp
  def perform(blob_id, officer_badge_id, latitude, longitude, captured_at)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob
    return unless blob.content_type&.start_with?("image/")

    # Idempotency: skip if already watermarked
    return if blob.metadata&.dig("watermarked")

    # Store pre-watermark checksum for forensic audit
    original_checksum = blob.checksum

    blob.open do |tempfile|
      watermarked_path = apply_watermark(
        tempfile.path,
        badge_id: officer_badge_id,
        lat: latitude,
        lng: longitude,
        timestamp: captured_at
      )

      # Re-upload the watermarked image to the same blob
      File.open(watermarked_path, "rb") do |f|
        blob.upload(f)
      end

      # Clean up temp file
      File.delete(watermarked_path) if File.exist?(watermarked_path)
    end

    # Update blob metadata with watermark audit trail
    blob.update!(
      metadata: (blob.metadata || {}).merge(
        "watermarked" => true,
        "watermarked_at" => Time.current.iso8601,
        "original_checksum" => original_checksum,
        "watermark_officer" => officer_badge_id,
        "watermark_gps" => { "lat" => latitude, "lng" => longitude },
        "watermark_timestamp" => captured_at
      )
    )

    Rails.logger.info "[WatermarkEvidenceJob] Watermarked blob #{blob_id} for officer #{officer_badge_id}"
  end

  private

  def apply_watermark(image_path, badge_id:, lat:, lng:, timestamp:)
    require "mini_magick"

    image = MiniMagick::Image.open(image_path)

    # Build watermark text
    ts_display = begin
      Time.parse(timestamp).strftime("%b %d, %Y %H:%M UTC")
    rescue StandardError
      timestamp.to_s
    end

    gps_display = if lat.present? && lng.present?
      "#{lat.to_f.round(6)}, #{lng.to_f.round(6)}"
    else
      "No GPS"
    end

    line1 = ts_display
    line2 = gps_display
    line3 = "Officer: #{badge_id}"

    # Scale font to image size — min 14px, proportional to width
    img_width  = image.width
    img_height = image.height
    font_size  = [img_width / 40, 14].max
    padding    = (font_size * 0.6).to_i
    band_height = (font_size * 4.5).to_i
    band_width  = [font_size * 20, (img_width * 0.45).to_i].max

    # Clamp band dimensions to image bounds
    band_x_start = [img_width - band_width, 0].max
    band_y_start = [img_height - band_height, 0].max

    # Single combine_options call — one ImageMagick subprocess for everything
    image.combine_options do |c|
      # Strip EXIF/metadata — privacy + smaller file
      c.strip

      # Draw semi-transparent dark band at bottom-right
      c.fill "rgba(0, 0, 0, 0.55)"
      c.draw "rectangle #{band_x_start},#{band_y_start} #{img_width},#{img_height}"

      # White text annotation
      c.fill "white"
      c.pointsize font_size.to_s
      c.gravity "SouthEast"

      # Line 3 (bottom) — Officer badge
      c.annotate "+#{padding}+#{padding}", line3

      # Line 2 (middle) — GPS
      c.annotate "+#{padding}+#{padding + font_size + 4}", line2

      # Line 1 (top) — Timestamp
      c.annotate "+#{padding}+#{padding + (font_size + 4) * 2}", line1

      # Compress output — quality 80 is good enough for evidence chain
      c.quality "80"

      # Sampling factor for smaller JPEG files
      c.sampling_factor "4:2:0"
    end

    output_path = "#{image_path}_watermarked.jpg"
    image.write(output_path)
    output_path
  end
end
