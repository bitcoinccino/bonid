class MainController < ApplicationController
  # app/controllers/main_controller.rb
  def home
    if user_signed_in?
      return redirect_to after_sign_in_path_for(current_user) unless request.path == after_sign_in_path_for(current_user)
    elsif current_officer.present?
      return redirect_to officer_dashboard_path unless request.path == officer_dashboard_path
    end

  end
  

  # app/controllers/main_controller.rb
def partners
  
end


def required_documents
  # Renders app/views/main/required_documents.html.erb
end
  
  # Legal documents (renders terms.html.erb and privacy.html.erb)
  def terms
    # Renders app/views/main/terms.html.erb
  end

  def privacy
    # Renders app/views/main/privacy.html.erb
  end

  # Public verified partners listing
  def partners
    @partners = Partner.where.not(verified_at: nil).order(:name).limit(6)# Renders app/views/main/partners.html.erb
  end

  # Entry point from /start?partner=slug
 # app/controllers/main_controller.rb
def start
  if params[:partner].present?
    @partner = Partner.find_by(slug: params[:partner])

    if @partner&.verified_at.present?
      session[:bonid_partner_id] = @partner.id
    else
      redirect_to partners_path, alert: "🚫 This partner is not yet verified." and return
    end

  elsif Rails.application.config.allow_public_signup
    session[:bonid_partner_id] = nil
    # Render organic signup page (as-is)
  else
    # ✅ Redirect to verified partners index
    redirect_to partners_path, alert: "ℹ️ Please choose a verified partner to begin." and return
  end
end

end

  
  


  

  
