class Admin::GuidelinesController < Admin::ApplicationController
  skip_before_action :ensure_guidelines_confirmed, only: [ :index, :confirm ]

  def index
    @guidelines = guidelines
  end

  def confirm
    if params[:confirmed] == "1"
      session[:admin_guidelines_confirmed] = true
      redirect_to admin_root_path, notice: "✅ Guidelines confirmed."
    else
      redirect_to admin_guidelines_path, alert: "Please check the box to confirm before proceeding."
    end
  end

  private

  # Centralized list of admin guidelines—grouped for readability
  def guidelines
    [
      # Data Security
      "Encrypt user data during storage and transmission to prevent unauthorized access.",
      "Access user data only for authorized purposes, such as verification or support.",
      "Limit data retention to the minimum required period as per BonID protocol.",
      "Implement multi-factor authentication for all admin access to sensitive systems.",

      # Privacy & Compliance
      "Do not share user data with third parties without explicit consent.",
      "Comply with Haiti's data protection regulations and international privacy standards (e.g., GDPR principles).",
      "Enable users to revoke consent and delete their data at any time.",
      "Conduct regular privacy impact assessments for new features involving identity data.",

      # Ethical Use & Accountability
      "Use BonID's scan logs to audit identity checks and ensure accountability.",
      "Report any data breaches or suspicious activity immediately to BonID's security team.",
      "Mitigate bias in verification processes by regularly reviewing algorithms and training data.",
      "Train staff on ethical data handling practices to maintain user trust and avoid discrimination.",

      # Incident Response & Updates
      "Develop and test incident response plans for data security events.",
      "Stay updated on evolving privacy laws and update guidelines accordingly."
    ]
  end
end
