# app/controllers/officers/profiles_controller.rb
module Officers
 class Officers::ProfilesController < Officers::BaseController

    before_action :authenticate_officer!

    def edit
      @officer = current_officer
      @officer.build_address if @officer.address.blank?
    end
    

    def update
      @officer = current_officer
      if @officer.update(officer_profile_params)
        redirect_to officers_dashboard_path, notice: "Profile updated successfully."
      else
        flash.now[:alert] = "Please fix the errors below."
        render :edit
      end
    end

    private

    def officer_profile_params
      # Name fields (first_name, middle_name, last_name) are intentionally excluded.
      # Names are sourced exclusively from the citizen's BonID profile (users table)
      # and synced one-way to officers via the User#sync_name_to_officer callback.
      params.require(:officer).permit(
        :photo, :email, :phone_number,
        :badge_id, :rank, :unit_name, :unit_type, :department_directorate, :signature_data,
        address_attributes: [
          :id, :department_id, :arrondissement_id, :commune_id,
          :communal_section_id, :postal_code, :street_address, :locality
        ]
      )
    end
  end
end