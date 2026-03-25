# app/controllers/api/v1/citizen/consent_grants_controller.rb
module Api
  module V1
    module Citizen
      class ConsentGrantsController < ApplicationController
        skip_before_action :verify_authenticity_token

        def approve_consent
          @grant = ConsentGrant.find_by(grant_token: params[:grant_token])

          if @grant.nil?
            respond_to do |format|
              format.html { render :approve_consent, status: :not_found }
              format.json { render json: { error: "Invalid or missing grant token" }, status: :not_found }
            end
            return
          end

          if @grant.expired?
            @grant.update!(status: :expired)
            respond_to do |format|
              format.html { render :approve_consent, status: :gone }
              format.json { render json: { error: "This consent link has expired." }, status: :gone }
            end
            return
          end

          case params[:decision]
          when "approve"
            @grant.update!(status: :approved, granted_at: Time.current)
            System::OauthNotifier.consent_approved(@grant).deliver_later
            ConsentWebhookJob.perform_later(@grant.id, "consent.approved") rescue nil
          when "reject"
            @grant.update!(status: :revoked, revoked_at: Time.current)
            System::OauthNotifier.consent_revoked(@grant).deliver_later
            ConsentWebhookJob.perform_later(@grant.id, "consent.revoked") rescue nil
          else
            respond_to do |format|
              format.html { render plain: "Invalid decision parameter", status: :bad_request }
              format.json { render json: { error: "Invalid decision parameter" }, status: :bad_request }
            end
            return
          end

          # ✅ Dual output for both browser clicks and API requests
          respond_to do |format|
            format.html { render :approve_consent }
            format.json do
              render json: {
                message: "Consent #{params[:decision]}ed successfully",
                status: @grant.status,
                partner: @grant.partner.name
              }, status: :ok
            end
          end
        end
      end
    end
  end
end
