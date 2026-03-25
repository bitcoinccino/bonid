# app/controllers/profiles_controller.rb
class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
  end

  def edit
    @user = current_user

    # Ensure nested associations exist
    @user.build_address if @user.address.blank?
    @user.emergency_contacts.build if @user.emergency_contacts.blank?
    @user.social_handles.build if @user.social_handles.blank?
    @user.build_physical_profile if @user.physical_profile.blank?
    @user.build_health_profile if @user.health_profile.blank?

    preload_departments
  end

  def update
    @user = current_user
    was_incomplete = !profile_complete?(@user)

    if @user.update(user_params)
      # ✅ Auto-generate BonID only for citizens
      if @user.citizen? && @user.bonid.blank?
        @user.generate_bonid!
      end

      # Redirect if profile just became complete
      if was_incomplete && profile_complete?(@user)
        flash[:notice] = "Profile completed successfully! Now submit your BonID verification."
        return redirect_to new_identity_submission_path
      end

      flash[:notice] = "Profile updated successfully!"
      redirect_to user_dashboard_path
    else
      preload_departments
      flash.now[:alert] = "Please fix the errors below."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # Preload Haiti’s full department hierarchy for dropdowns
  def preload_departments
    @departments = Department.includes(arrondissements: { communes: :communal_sections }).all.map do |department|
      {
        id: department.id,
        name: department.name,
        arrondissements: department.arrondissements.map do |arrondissement|
          {
            id: arrondissement.id,
            name: arrondissement.name,
            communes: arrondissement.communes.map do |commune|
              {
                id: commune.id,
                name: commune.name,
                postal_code: commune.postal_code_digit || "HT0000",
                sections: commune.communal_sections.map do |cs|
                  { id: cs.id, name: cs.name }
                end
              }
            end
          }
        end
      }
    end
  end

  # Strong params for user and nested attributes
  def user_params
    params.require(:user).permit(
      :photo,
      :first_name, :middle_name, :last_name, :sex, :dob, :phone,
      :marital_status, :id_type, :id_number,
      :birth_department_id, :birth_commune_id,
      :place_of_birth, :nationality, :id_issued_on, :id_expires_on,
      :cin_unique_id, :issuing_authority,
      address_attributes: [
        :id, :street_address, :postal_code, :locality, :country,
        :department_id, :arrondissement_id, :commune_id, :communal_section_id
      ],
      emergency_contacts_attributes: [
        :id, :name, :phone, :email, :relation, :address, :bonid, :_destroy
      ],
      social_handles_attributes: [
        :id, :platform, :handle, :active, :since, :until, :_destroy
      ],
      health_profile_attributes: [
        :id, :blood_type, :allergies, :chronic_conditions,
        :medications, :organ_donor
      ],
      physical_profile_attributes: [
        :id, :weight_kg, :height_cm, :race, :eye_color, :hair_color,
        :tattoos, :scars,
        :body_type, :skin_tone, :facial_hair, :handedness
      ]
    )
  end
end
