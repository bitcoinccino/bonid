# frozen_string_literal: true

# Citizens::OnboardingController
# ==============================
# One-question gate that fires once after OTP signup, before the citizen
# touches the profile wizard / dashboard. Captures whether they live in
# Haiti or abroad so the entire downstream UX (profile address fields,
# dashboard "Sa Ou Bezwen" checklist, submission document branch) can
# pre-configure for the right path.
#
# When a WaitlistSignup#country_of_residence already exists for the
# citizen's email, the gate auto-answers and the splash page never shows.
module Citizens
  class OnboardingController < BaseController
    # Skip the gate-redirect on this controller itself (otherwise the gate
    # would loop forever) and don't require profile completion etc.
    skip_before_action :require_diaspora_answer!, raise: false

    def show
      # Pre-fill from waitlist if available, then redirect on through.
      if (suggested = waitlist_country_for(current_citizen)).present?
        current_citizen.update_columns(is_diaspora: suggested != "HT")
        redirect_to redirect_target and return
      end

      @citizen = current_citizen
    end

    def update
      choice = params[:is_diaspora].to_s
      unless %w[true false].include?(choice)
        flash.now[:alert] = "Tanpri chwazi yon opsyon."
        @citizen = current_citizen
        return render :show, status: :unprocessable_entity
      end

      if current_citizen.update(is_diaspora: choice == "true")
        redirect_to redirect_target, notice: "Mèsi! Anrejistreman ap kòmanse."
      else
        flash.now[:alert] = current_citizen.errors.full_messages.to_sentence.presence ||
                            "Pa kapab sove repons lan."
        @citizen = current_citizen
        render :show, status: :unprocessable_entity
      end
    end

    private

    # Forward to wherever the citizen was trying to go before the gate
    # interrupted them, falling back to the profile wizard (the natural
    # next step right after signup).
    def redirect_target
      stored = session.delete(:after_onboarding_redirect_to)
      stored.presence || edit_citizens_profile_path
    end

    # Best-effort: if the citizen signed the public waitlist, treat that
    # answer as authoritative so we don't ask the same question twice.
    def waitlist_country_for(citizen)
      return nil if citizen.email.blank?
      WaitlistSignup.where(email: citizen.email)
                    .order(created_at: :desc)
                    .pick(:country_of_residence)
    end
  end
end
