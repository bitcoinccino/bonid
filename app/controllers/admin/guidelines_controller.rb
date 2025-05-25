module Admin
  class GuidelinesController <  Admin::ApplicationController
    before_action :authenticate_user!
    skip_before_action :ensure_guidelines_confirmed, only: [:index, :confirm]

    def index
      @guidelines = [
        "Review submissions fairly and accurately.",
        "Do not share user data outside the platform.",
        "Only access submissions when necessary for review.",
        "Ensure rejection reasons are selected and documented.",
        "Report any suspicious documents to the security team."
      ]
    end

    def confirm
      if params[:confirmed] == "1"
        session[:admin_guidelines_confirmed] = true
        redirect_to admin_identity_submissions_path, notice: "Guidelines confirmed. Welcome to the admin dashboard."
      else
        redirect_to admin_guidelines_path, alert: "Please check the box to confirm before proceeding."
      end
    end
end
end
