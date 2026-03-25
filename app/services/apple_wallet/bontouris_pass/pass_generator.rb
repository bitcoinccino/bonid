require "json"
require "openssl"
require "zip"

class AppleWallet::PassGenerator
  CERT_PATH = Rails.root.join("certs/apple/pass.p12")

  def initialize(visitor)
    @visitor = visitor
  end

  def generate!
    Dir.mktmpdir do |dir|
      build_pass_json(dir)
      add_images(dir)
      create_manifest(dir)
      sign_manifest(dir)
      zip_pass(dir)
    end
  end

  private

  def build_pass_json(dir)
    File.write("#{dir}/pass.json", pass_payload.to_json)
  end

  def pass_payload
    {
      formatVersion: 1,
      passTypeIdentifier: "pass.verifyem.bontouris",
      serialNumber: @visitor.bonid,
      teamIdentifier: ENV["APPLE_TEAM_ID"],
      organizationName: "Verifyem",
      description: "BonTouris Digital Visitor ID",
      logoText: "BonTouris ID",
      expirationDate: @visitor.expires_at.iso8601,
      barcode: {
        format: "PKBarcodeFormatQR",
        message: verification_url,
        messageEncoding: "iso-8859-1"
      }
    }
  end

  def verification_url
    Rails.application.routes.url_helpers.verify_visitor_url(
      @visitor.bonid,
      host: "verifyem.ht"
    )
  end

  def zip_pass(dir)
    zip_path = "#{dir}.pkpass"

    Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
      Dir["#{dir}/*"].each do |file|
        zip.add(File.basename(file), file)
      end
    end

    File.read(zip_path)
  end
end
