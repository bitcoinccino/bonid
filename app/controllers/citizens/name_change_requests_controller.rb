# app/controllers/citizens/name_change_requests_controller.rb
module Citizens
  class NameChangeRequestsController < BaseController
    before_action :ensure_verified

    def new
      @name_change_request = current_citizen.name_change_requests.build
    end

    def create
      @name_change_request = current_citizen.name_change_requests.build(request_params)

      if @name_change_request.save
        UserMailer.name_change_submitted(current_citizen, @name_change_request).deliver_later

        redirect_to citizens_dashboard_path,
                    notice: "Your name change request has been submitted for review. A confirmation email has been sent."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def ensure_verified
      unless current_citizen.identity_submissions.exists?(status: :approved)
        redirect_to citizens_profile_path,
                    alert: "You must have a verified identity to request a name change."
      end
    end

    def request_params
      params.require(:name_change_request).permit(
        :new_first_name, :new_middle_name, :new_last_name,
        :reason, :other_reason, :supporting_document
      )
    end
  end
end
