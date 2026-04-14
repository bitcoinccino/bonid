# frozen_string_literal: true

module Citizens
  class DashboardController < Citizens::BaseController
    before_action :authenticate_citizen!
    before_action :set_citizen
    before_action :build_missing_profile_associations  # ← THIS IS THE KEY FIX

    def index
      @profile_completion = @citizen.profile_completion_percentage
      @profile_complete = @citizen.profile_complete?
      @submissions = @citizen.identity_submissions
                             .includes(:qr_scan_logs)
                             .order(created_at: :desc)
      @last_submission = @submissions.first
      @approved_submission = @submissions.find(&:status_approved?)

      # Pending transaction consents (banks, wallets requesting approval)
      @pending_consents = @citizen.transaction_consents
                                  .active
                                  .includes(:partner)
                                  .order(expires_at: :asc)
                                  .limit(5)

      # Waitlist data — used to tailor the "What You'll Need" checklist
      # for domestic vs diaspora applicants
      @waitlist = WaitlistSignup.find_by(email: @citizen.email)
      @is_diaspora = @waitlist&.diaspora? || @citizen.address&.country.present? && @citizen.address.country.upcase != "HAITI" && @citizen.address.country.upcase != "HT"
      @residence_country = @waitlist&.country_of_residence || (@is_diaspora ? @citizen.address&.country : "HT")
    end

    private

    def set_citizen
      @citizen = current_citizen
    end

    # =================================================================
    # Build missing associated records so modals always show form fields
    # =================================================================
    def build_missing_profile_associations
      # has_one associations — build if missing
      @citizen.build_health_profile      unless @citizen.health_profile
      @citizen.build_physical_profile   unless @citizen.physical_profile

      # has_many associations — build one empty record if none exist
      # This ensures the nested form fields appear in modals
      @citizen.bank_profiles.build          if @citizen.bank_profiles.empty?
      @citizen.emergency_contacts.build     if @citizen.emergency_contacts.empty?
      @citizen.social_handles.build         if @citizen.social_handles.empty?
      # Eager-load linked user + photo for family card (avoids N+1)
      @citizen.family_members.includes(linked_user: { photo_attachment: :blob }).load
      @citizen.family_members.build         if @citizen.family_members.empty?
    end
  end
end
