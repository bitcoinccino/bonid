# app/services/qr_code_generator.rb
require "rqrcode"
require "chunky_png"
require "base64"

class QrCodeGenerator
  def self.generate_base64_svg(url:)
    qr = RQRCode::QRCode.new(url)

    svg = qr.as_svg(
      offset: 0,
      color: '000',
      shape_rendering: 'crispEdges',
      module_size: 6,
      standalone: true
    )

    Base64.strict_encode64(svg)
  end

  def self.generate_base64_png(url:, logo_path: nil, size: 300)
    qr = RQRCode::QRCode.new(url)

    png = qr.as_png(
      bit_depth: 1,
      border_modules: 4,
      color_mode: ChunkyPNG::COLOR_RGB,
      color: 'black',
      fill: 'white',
      module_px_size: 6,
      size: size
    )

    if logo_path && File.exist?(logo_path)
      png = overlay_logo(png, logo_path)
    end

    Base64.strict_encode64(png.to_s)
  end

  private

  def self.overlay_logo(qr_png, logo_path)
    qr_img = ChunkyPNG::Image.from_blob(qr_png.to_s)
    logo_img = ChunkyPNG::Image.from_file(logo_path)

    # Resize logo if larger than 30% of QR size
    max_logo_size = (qr_img.width * 0.3).to_i
    logo_img.resample_bilinear!(max_logo_size, max_logo_size) if logo_img.width > max_logo_size

    x = (qr_img.width - logo_img.width) / 2
    y = (qr_img.height - logo_img.height) / 2

    qr_img.compose!(logo_img, x, y)
    qr_img
  end
end
