# frozen_string_literal: true

# Active Record Encryption Configuration
# Rails 7+ requires these keys for encrypted attributes

# Try to load from credentials first, fall back to environment variables or defaults
encryption_config = Rails.application.credentials.active_record_encryption || {}

primary_key = encryption_config[:primary_key] ||
              ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] ||
              "UVnE22s8TmolHT6sBae6sUlb9n0kEfmX"

deterministic_key = encryption_config[:deterministic_key] ||
                    ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] ||
                    "pUwJ82pJStZ58gkCTG3LsxMaKj2sJdBT"

key_derivation_salt = encryption_config[:key_derivation_salt] ||
                      ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] ||
                      "KxXwT1MmAPrhHznvTaqzJ5wzLum6hZJr"

Rails.application.config.active_record.encryption.primary_key = primary_key
Rails.application.config.active_record.encryption.deterministic_key = deterministic_key
Rails.application.config.active_record.encryption.key_derivation_salt = key_derivation_salt
