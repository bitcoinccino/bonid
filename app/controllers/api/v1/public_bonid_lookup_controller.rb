# frozen_string_literal: true

module Api
  module V1
    class PublicBonidLookupController < ApplicationController
      skip_before_action :authenticate_citizen!, raise: false
      skip_before_action :authenticate_partner!, raise: false

      def show
        identity = IdentitySubmission.approved.find_by(bonid: params[:bonid])
        return render json: { verified: false }, status: :ok unless identity

        user = identity.user
        return render json: { verified: false }, status: :ok unless user

        render json: {
          verified: true,
          name: "#{user.first_name} #{user.last_name}".strip,
          phone: user.phone,
          email: user.email,
          bonid: identity.bonid,
          user_id: user.id
        }, status: :ok
      end
    end
  end
end
