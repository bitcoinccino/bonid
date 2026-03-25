# frozen_string_literal: true

module Admin
  class ReviewersController < Admin::ApplicationController
    before_action :set_reviewer, only: [ :destroy ]

    # -------------------------------------------------------------
    # INDEX — List all reviewers
    # -------------------------------------------------------------
    def index
      @reviewers = User.with_role(:reviewer).order(created_at: :desc)
    end

    # -------------------------------------------------------------
    # NEW — Single reviewer invite form
    # -------------------------------------------------------------
    def new
      @reviewer = User.new
    end

    # -------------------------------------------------------------
    # CREATE — Admin invites a single reviewer
    # (NO BonID verification check here — per requirements)
    # -------------------------------------------------------------
    def create
      email = reviewer_params[:email].strip.downcase

      @reviewer = User.find_or_initialize_by(email: email)

      if @reviewer.new_record?
        @reviewer.password = SecureRandom.hex(10)
        @reviewer.save!
      end

      @reviewer.add_role(:reviewer) unless @reviewer.reviewer?

      # Devise invitation
      @reviewer.invite! unless @reviewer.invitation_token.present?

      PartnerAuditLog.log!(
        nil,
        current_admin_user,
        "reviewer_invited",
        { email: email }
      )

      redirect_to admin_reviewers_path,
        notice: "📨 Reviewer invitation sent to #{email}."
    end

    # -------------------------------------------------------------
    # BULK — Upload CSV of reviewer emails
    # (Still NO BonID check here)
    # -------------------------------------------------------------
    def bulk_new; end

    def bulk_create
      file = params[:csv]

      unless file&.content_type&.in?(%w[text/csv application/csv application/vnd.ms-excel])
        return redirect_to bulk_new_admin_reviewers_path,
          alert: "⚠️ Please upload a valid CSV."
      end

      invited = 0

      require "csv"
      CSV.foreach(file.path, headers: false) do |row|
        email = row.first.to_s.strip.downcase
        next if email.blank?

        user = User.find_or_initialize_by(email: email)

        if user.new_record?
          user.password = SecureRandom.hex(10)
          user.save!
        end

        user.add_role(:reviewer) unless user.reviewer?

        user.invite! unless user.invitation_token.present?

        invited += 1
      end

      PartnerAuditLog.log!(
        nil,
        current_admin_user,
        "reviewers_bulk_invited",
        { count: invited }
      )

      redirect_to admin_reviewers_path,
        notice: "📨 #{invited} reviewers invited."
    end

    # -------------------------------------------------------------
    # DESTROY — Remove reviewer role
    # -------------------------------------------------------------
    def destroy
      @reviewer.remove_role(:reviewer)

      PartnerAuditLog.log!(
        nil,
        current_admin_user,
        "reviewer_removed",
        { email: @reviewer.email }
      )

      redirect_to admin_reviewers_path,
        notice: "🗑️ Reviewer removed."
    end

    # -------------------------------------------------------------
    # PRIVATE
    # -------------------------------------------------------------
    private

    def set_reviewer
      @reviewer = User.find(params[:id])
    end

    def reviewer_params
      params.require(:user).permit(:email)
    end
  end
end
