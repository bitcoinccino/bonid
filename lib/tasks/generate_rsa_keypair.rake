# lib/tasks/generate_rsa_keypair.rake
#
# Generates an RSA-2048 keypair for RSASSA-PSS certificate signing.
# Run this once, then paste the output into `rails credentials:edit` under `bonid:`.
#
# Usage:
#   bundle exec rails bonid:generate_rsa_keypair
#
namespace :bonid do
  desc "Generate RSA-2048 keypair for RSASSA-PSS certificate signing. Paste output into credentials."
  task generate_rsa_keypair: :environment do
    require "openssl"

    puts "Generating RSA-2048 keypair..."
    key = OpenSSL::PKey::RSA.generate(2048)

    puts ""
    puts "=" * 70
    puts "Paste the following into: bundle exec rails credentials:edit"
    puts "=" * 70
    puts ""
    puts "bonid:"
    puts "  rsa_private_key: |"
    key.private_to_pem.each_line { |l| print "    #{l}" }
    puts ""
    puts "  rsa_public_key: |"
    key.public_to_pem.each_line { |l| print "    #{l}" }
    puts ""
    puts "=" * 70
    puts ""
    puts "Public key fingerprint (SHA-256):"
    puts "  " + OpenSSL::Digest::SHA256.hexdigest(key.public_to_pem)
    puts ""
    puts "After adding to credentials, serve the public key at:"
    puts "  GET /certs/public_key.pem"
    puts "  (so embassies and partners can verify signatures offline)"
    puts ""
  end
end
