# app/controllers/citizens/name_change_requests_controller.rb
module Citizens
  class NameChangeRequestsController < BaseController
    before_action :ensure_verified

    # New values start as the current ones, so fixing one letter is one edit.
    def new
      @name_change_request = current_citizen.name_change_requests.build(
        new_first_name:  current_citizen.first_name,
        new_middle_name: current_citizen.middle_name,
        new_last_name:   current_citizen.last_name,
        new_dob:         current_citizen.dob
      )
      @name_change_request.change_fields = []
    end

    def create
      @name_change_request = current_citizen.name_change_requests.build(request_params)

      if @name_change_request.save
        UserMailer.name_change_submitted(current_citizen, @name_change_request).deliver_later

        redirect_to citizens_dashboard_path,
                    notice: t("citizen_portal.name_change.flash.submitted")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def ensure_verified
      unless current_citizen.identity_submissions.exists?(status: :approved)
        redirect_to citizens_profile_path,
                    alert: t("citizen_portal.name_change.flash.must_be_verified")
      end
    end

    def request_params
      params.require(:name_change_request).permit(
        :new_first_name, :new_middle_name, :new_last_name, :new_dob,
        :reason, :other_reason, :supporting_document,
        change_fields: []
      )
    end
  end
end
