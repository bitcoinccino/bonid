# app/controllers/admin/name_change_requests_controller.rb
module Admin
  class NameChangeRequestsController < BaseController
    before_action :set_request, only: [ :show, :approve, :reject ]

    def index
      @requests = NameChangeRequest
        .includes(:user, :reviewed_by, supporting_document_attachment: :blob)
        .then { |scope| params[:status].present? ? scope.where(status: params[:status]) : scope }
        .recent_first
        .page(params[:page]).per(20)

      @counts = NameChangeRequest.group(:status).count
    end

    def show; end

    def approve
      @request.update!(
        status: :approved,
        reviewed_by: current_admin_user,
        reviewed_at: Time.current,
        admin_note: params[:admin_note]
      )

      UserMailer.name_change_approved(@request.user, @request).deliver_later

      redirect_to admin_name_change_requests_path,
                  notice: "Name change approved — #{@request.user.reload.full_name}."
    end

    def reject
      if params[:rejection_reason].blank?
        redirect_to admin_name_change_request_path(@request),
                    alert: "Rejection reason is required."
        return
      end

      @request.update!(
        status: :rejected,
        reviewed_by: current_admin_user,
        reviewed_at: Time.current,
        rejection_reason: params[:rejection_reason],
        admin_note: params[:admin_note]
      )

      UserMailer.name_change_rejected(@request.user, @request).deliver_later

      redirect_to admin_name_change_requests_path,
                  notice: "Name change request rejected."
    end

    private

    def set_request
      @request = NameChangeRequest.find(params[:id])
    end
  end
end
