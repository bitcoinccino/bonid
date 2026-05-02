class AddIsDiasporaToUsers < ActiveRecord::Migration[8.0]
  def change
    # Nullable on purpose: `nil` means the citizen has not yet answered the
    # one-question onboarding gate. `false` means Haiti, `true` means abroad.
    # Citizens with WaitlistSignup#country_of_residence get pre-filled by the
    # gate controller so they only confirm with one tap.
    add_column :users, :is_diaspora, :boolean
    add_index  :users, :is_diaspora
  end
end
