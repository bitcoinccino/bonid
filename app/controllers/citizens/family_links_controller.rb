# frozen_string_literal: true

module Citizens
  class FamilyLinksController < ApplicationController
    # No login required — the token IS the authentication
    skip_before_action :authenticate_user!, raise: false

    # GET /family/confirm?token=abc123
    def confirm
      fm = FamilyMember.find_by(link_consent_token: params[:token])

      if fm.nil?
        flash[:alert] = t("alerts.family.invalid_link")
        redirect_to root_path and return
      end

      if fm.link_confirmed?
        flash[:info] = t("alerts.family.already_confirmed")
        redirect_to root_path and return
      end

      fm.confirm_link!(ip: request.remote_ip)
      fm.update!(verification_status: :verified)

      # Real-time update on the citizen's dashboard — rendered in *their*
      # portal language, not the confirming visitor's.
      I18n.with_locale(fm.user.portal_locale) do
        Turbo::StreamsChannel.broadcast_replace_to(
          "citizen_#{fm.user_id}_family",
          target: "family-member-#{fm.id}",
          partial: "citizens/dashboard/family_member_item",
          locals: { fm: fm }
        )
      end

      flash[:success] = t("alerts.family.confirmed", name: "#{fm.user.first_name} #{fm.user.last_name}")
      redirect_to root_path
    end

    # GET /family/deny?token=abc123
    def deny
      fm = FamilyMember.find_by(link_consent_token: params[:token])

      if fm.nil?
        flash[:alert] = t("alerts.family.invalid_link")
        redirect_to root_path and return
      end

      if fm.link_confirmed?
        flash[:info] = t("alerts.family.already_confirmed_support")
        redirect_to root_path and return
      end

      # Remove the link, keep manual data, and flag to prevent spam
      denied_user_id = fm.linked_user_id
      fm.update!(
        linked_user_id: nil,
        linked_bonid: nil,
        link_consent_token: nil,
        verification_status: :manual_entry,
        metadata: fm.metadata.merge(
          "link_denied_at" => Time.current.iso8601,
          "link_denied_ip" => request.remote_ip,
          "denied_user_id" => denied_user_id,
          "deny_count" => (fm.metadata["deny_count"].to_i + 1)
        )
      )

      flash[:info] = t("alerts.family.declined")
      redirect_to root_path
    end
  end
end
