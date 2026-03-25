namespace :data do
  desc "Move all BankAccount records into BankProfile"
  task migrate_bank_accounts_to_bank_profiles: :environment do
    migrated = 0

    BankAccount.find_each do |acc|
      next if BankProfile.exists?(user_id: acc.user_id, account_number: acc.account_number)

      BankProfile.create!(
        user_id: acc.user_id,
        bank_name: acc.bank_name,
        account_number: acc.account_number,
        account_type: acc.account_type,
        currency: acc.currency,
        kyc_verified: acc.currently_open,
        verification_source: "Legacy Migration",
        last_synced_at: acc.updated_at,
        metadata: {
          legacy_table: "bank_accounts",
          opened_on: acc.opened_on,
          closed_on: acc.closed_on,
          migrated_at: Time.current
        }
      )
      migrated += 1
    end

    puts "✅ Done. Migrated #{migrated} bank_accounts to bank_profiles."
  end
end
