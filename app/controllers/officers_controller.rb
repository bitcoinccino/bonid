class OfficersController < ApplicationController
  before_action :authenticate_officer!
  before_action :require_officer!
  before_action :set_officer

  def dashboard
    @incidents = current_officer.incident_reports.order(created_at: :desc).limit(10)
  end

  def show
  end

  def edit
    @officer.build_address if @officer.address.blank?
  end

  def update
    if @officer.update(officer_params)
      if params[:officer][:signature_data].present?
        @officer.attach_signature_from_data_url(params[:officer][:signature_data])
      end

      redirect_to officer_path(@officer), notice: "Profile updated successfully."
    else
      flash.now[:alert] = "There were errors updating your profile."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_officer
    @officer = current_officer
  end

  def officer_params
    params.require(:officer).permit(
      :first_name, :middle_name, :last_name, :sex, :dob,
      :phone_number, :email, :password, :password_confirmation,
      :badge_id, :rank, :unit_name, :unit_type,
      :signature_data,
      address_attributes: [
        :id, :department_id, :arrondissement_id, :commune_id,
        :communal_section_id, :street_address, :postal_code, :latitude, :longitude
      ]
    )
  end
end



# 2. ✅ Add 2FA logic (Two-Factor Authentication)
# Purpose: Adds extra security for officer logins — especially critical for law enforcement systems.

# How it works:
# After the officer logs in with their password, the system can:

# Send a one-time code (via email or SMS).

# Require the officer to input the code before accessing sensitive areas like dashboard or manual lookup.

# Typical implementation:

# Add a 2fa_code column to the Officer model.

# Generate/send a 6-digit token during login.

# Store it in session until verified.

# Protect actions like this:


# before_action :require_2fa_verification

# def require_2fa_verification
#   unless session[:officer_2fa_verified]
#     redirect_to verify_2fa_path
#   end
# end