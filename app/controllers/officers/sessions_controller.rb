# app/controllers/officers/sessions_controller.rb
class Officers::SessionsController < Devise::SessionsController
  def destroy
    # Sign out with Devise
    super do
      # Clear any additional session keys
      session.delete(:officer_id)
      session.delete(:bonid_partner_id)
    end
  end

  protected

  def after_sign_in_path_for(resource)
    officer_dashboard_path
  end

  def after_sign_out_path_for(resource_or_scope)
    session.delete(:officer_id)
    session.delete(:bonid_partner_id)
    root_path
  end
end

