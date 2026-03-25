# app/controllers/admin/verification_records_controller.rb
# frozen_string_literal: true

module Admin
  class VerificationRecordsController < Admin::BaseController
    before_action :set_record, only: [ :show, :update ]

    def index
      @records = VerificationRecord.order(created_at: :desc)
    end

    def show; end

    def update
      if params[:status].present?
        @record.update(status: params[:status], verified_at: Time.current)
        UserMailer.record_status_update(@record.user, @record).deliver_later
        redirect_to admin_verification_records_path, notice: "✅ Record updated successfully."
      else
        redirect_to admin_verification_records_path, alert: "⚠️ No status provided."
      end
    end

    private

    def set_record
      @record = VerificationRecord.find(params[:id])
    end
  end
end
