# frozen_string_literal: true

module Admin
  class CommunesController < BaseController
    before_action :set_commune

    # Go live in a commune: flips the launched gate and emails every still-waiting
    # signup there that they can now register (no invite code needed).
    def launch
      @commune.launch!
      notified = notify_waiting_signups(@commune)

      redirect_back fallback_location: admin_waitlist_signups_path(commune_id: @commune.id),
                    notice: "#{@commune.name} is now live. " \
                            "Notified #{notified} waiting signup#{'s' unless notified == 1}."
    end

    def unlaunch
      @commune.unlaunch!

      redirect_back fallback_location: admin_waitlist_signups_path(commune_id: @commune.id),
                    notice: "#{@commune.name} unlaunched — new signups there will wait again."
    end

    private

    def set_commune
      @commune = Commune.find(params[:id])
    end

    # Idempotent: only emails signups still "waiting", and flips them to
    # "invited" so a later unlaunch/relaunch never double-notifies anyone.
    def notify_waiting_signups(commune)
      count = 0
      WaitlistSignup.where(commune_id: commune.id, status: "waiting").find_each do |signup|
        WaitlistMailer.commune_launched(signup).deliver_later
        signup.mark_invited!
        count += 1
      end
      count
    end
  end
end
