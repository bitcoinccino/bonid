# app/controllers/profiles_controller.rb
class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
  end
  

  def edit
    @user = current_user
    @user.build_address if @user.address.blank?

    # Preload departments with nested associations for offline support
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
                postal_code: commune.postal_code_digit || "HT0000", # Map postal_code_digit to postal_code for frontend
                sections: commune.communal_sections.map do |communal_section|
                  {
                    id: communal_section.id,
                    name: communal_section.name
                  }
                end
              }
            end
          }
        end
      }
    end
  end

  def update
    @user = current_user
  
    if @user.update(user_params)
      if @user.bonid.blank?
        @user.generate_bonid
        @user.save
      end
  
      # unless @user.admin? || @user.reviewer?
      #   UserMailer.welcome_email(@user).deliver_later
      # end
  
      flash[:notice] = "Profile completed successfully!"
      redirect_to user_dashboard_path # ✅ Redirect here
    else
      # Rebuild departments for failed form re-render
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
                  sections: commune.communal_sections.map { |cs| { id: cs.id, name: cs.name } }
                }
              end
            }
          end
        }
      end
  
      flash.now[:alert] = "Please fix the errors below."
      render :edit, status: :unprocessable_entity
    end
  end
  

  private

  def user_params
    params.require(:user).permit(
      :first_name, :middle_name, :last_name, :sex, :dob, :phone,
      :marital_status, :social_handle, :id_type, :id_number,
      :place_of_birth, :nationality, :id_issued_on, :id_expires_on,
      :issuing_authority,
      address_attributes: [
        :id, :street_address, :postal_code, :locality, :country,
        :department_id, :arrondissement_id, :commune_id, :communal_section_id
      ]
    )
  end
end

