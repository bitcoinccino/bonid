# frozen_string_literal: true

module PartnerPortal
  module LawEnforcement
    class ApiKeysController < PartnerPortal::LawEnforcement::BaseController
      layout "partner_portal/law_enforcement"
      before_action :load_api_stats, only: [ :index ]
      before_action :load_recent_lookups, only: [ :index ]
      before_action :load_consent_grants, only: [ :index ]
      before_action :load_suspect_alerts, only: [ :index ]

      def index
        @partner = @current_partner
        @new_api_key_token = flash[:new_api_key_token]
      end

      # Regenerate the partner's API key (using create action for POST /api_keys)
      def create
        new_key = @current_partner.rotate_api_key!
        flash[:new_api_key_token] = new_key
        redirect_to partner_portal_law_enforcement_api_keys_path,
                    notice: "API Key regenerated successfully."
      end

      # Alias for regenerate (member action)
      def regenerate
        create
      end

      private

      # Load API usage statistics
      def load_api_stats
        logs = @current_partner.api_access_logs
        @api_stats = {
          total: logs.count,
          success: logs.where(success: true).count,
          failed: logs.where(success: false).count
        }

        @api_stats[:success_rate] = if @api_stats[:total] > 0
          ((@api_stats[:success].to_f / @api_stats[:total]) * 100).round(1)
        else
          0
        end
      end

      # Load recent BonID lookups from API access logs (with identity submissions for photos)
      def load_recent_lookups
        @recent_lookups = @current_partner.api_access_logs
                            .includes(user: :identity_submissions)
                            .order(created_at: :desc)
                            .limit(20)
      end

      # Load citizens who have granted consent to this partner
      def load_consent_grants
        @consent_grants = @current_partner.consent_grants
                            .includes(citizen: :identity_submissions)
                            .order(created_at: :desc)

        @consent_stats = {
          total: @consent_grants.count,
          active: @consent_grants.where(status: :approved).where("expires_at > ?", Time.current).count,
          pending: @consent_grants.where(status: :pending).count,
          revoked: @consent_grants.where(status: :revoked).count
        }
      end

      # Builds a Set of user_ids that have active suspect alerts.
      # Used in the view for O(1) flag checks on consent grants and recent lookups.
      def load_suspect_alerts
        consent_user_ids = @consent_grants&.map(&:citizen_id)&.compact || []
        lookup_user_ids  = @recent_lookups&.map(&:user_id)&.compact || []
        all_user_ids     = (consent_user_ids + lookup_user_ids).uniq

        if all_user_ids.any?
          # Check by user_id
          flagged_ids = SuspectAlert.active
                          .where(user_id: all_user_ids)
                          .pluck(:user_id)

          # Also check by BonID for dual-match (same pattern as SuspectAlert.check_user)
          users_with_bonids = User.where(id: all_user_ids)
                                  .where.not(bonid: [ nil, "" ])
                                  .pluck(:id, :bonid)

          bonids = users_with_bonids.map(&:last)
          bonid_flagged = if bonids.any?
            SuspectAlert.active.where(bonid: bonids).pluck(:bonid)
          else
            []
          end

          bonid_to_user = users_with_bonids.to_h { |id, bonid| [ bonid, id ] }
          bonid_flagged_ids = bonid_flagged.filter_map { |b| bonid_to_user[b] }

          @suspect_user_ids = Set.new(flagged_ids + bonid_flagged_ids)
        else
          @suspect_user_ids = Set.new
        end
      end
    end
  end
end
