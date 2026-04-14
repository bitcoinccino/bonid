# frozen_string_literal: true

# Handles anonymous post-vote feedback from pilot testers.
# No authentication required — same as the public verify page.
#
# POST /election/feedback  — submit survey (returns JSON)
# GET  /election/feedback/stats — aggregate results (admin, optional auth)
#
module Election
  class PilotFeedbackController < ApplicationController
    skip_before_action :authenticate_user!, raise: false
    skip_before_action :authenticate_citizen!, raise: false
    skip_forgery_protection only: [:create]

    # POST /election/feedback
    def create
      feedback = PilotFeedback.new(feedback_params)
      feedback.ip_country = request.headers["CF-IPCountry"] || IpGeolocator.country_code(request.remote_ip) rescue nil
      feedback.user_agent = request.user_agent&.truncate(255)

      if feedback.save
        render json: { status: "success", message: "Mèsi! Ou fèk ede Ayiti." }, status: :created
      else
        render json: { status: "error", errors: feedback.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # GET /election/feedback/stats
    def stats
      election_id = params[:election_id] || "2026-test-pilot-1"
      @stats = PilotFeedback.stats(election_id)
      @feedbacks = PilotFeedback.for_election(election_id)
                                .where.not(comment: [nil, ""])
                                .order(created_at: :desc)
                                .limit(50)

      render json: {
        election_id: election_id,
        stats: @stats,
        recent_comments: @feedbacks.map { |f|
          {
            trust_level: f.trust_level,
            trust_label: PilotFeedback::TRUST_LABELS[f.trust_level],
            comment: f.comment,
            lang: f.lang,
            channel: f.channel,
            created_at: f.created_at.iso8601
          }
        }
      }
    end

    private

    def feedback_params
      params.require(:pilot_feedback).permit(
        :election_id, :receipt_id, :ballot_hash,
        :time_to_vote, :photo_clarity, :trust_level,
        :comment, :lang, :channel, :consulate_id
      )
    end
  end
end
