# frozen_string_literal: true

module Admin
  class WaitlistSignupsController < BaseController
    def index
      @signups = WaitlistSignup.includes(:commune, :partner).order(created_at: :desc)
      @signups = @signups.where(signup_type: params[:type]) if params[:type].present?
      @signups = @signups.where(status: params[:status]) if params[:status].present?
      @signups = @signups.where(diaspora: true) if params[:diaspora] == "1"
      @signups = @signups.where("email ILIKE ?", "%#{params[:search]}%") if params[:search].present?

      # Department → Commune cascade filter
      if params[:department_id].present?
        commune_ids = Commune.where(department_id: params[:department_id]).pluck(:id)
        @signups = @signups.where(commune_id: commune_ids)
      end
      @signups = @signups.where(commune_id: params[:commune_id]) if params[:commune_id].present?

      @total = WaitlistSignup.count
      @citizens = WaitlistSignup.citizens.count
      @businesses = WaitlistSignup.businesses.count
      @diaspora_count = WaitlistSignup.diaspora_signups.count
      @top_communes = WaitlistSignup.where.not(commune_id: nil)
                                    .group(:commune_id)
                                    .count
                                    .sort_by { |_, v| -v }
                                    .first(10)
                                    .map { |id, count| [Commune.find(id).name, count] }

      @departments = Department.order(:name)
      @communes = if params[:department_id].present?
                    Commune.where(department_id: params[:department_id]).order(:name)
                  else
                    Commune.order(:name)
                  end
      # When filtered to a single commune, expose it so the view can offer
      # the "Launch commune" action.
      if params[:commune_id].present?
        @selected_commune = Commune.find_by(id: params[:commune_id])
        if @selected_commune
          @selected_commune_waiting =
            WaitlistSignup.where(commune_id: @selected_commune.id, status: "waiting").count
        end
      end

      @signups = @signups.page(params[:page]).per(25)
    end

    def show
      @signup = WaitlistSignup.find(params[:id])
    end

    def invite
      signup = WaitlistSignup.find(params[:id])
      invite_code = generate_invite_code(signup)
      signup.mark_invited!
      WaitlistMailer.invitation(signup, invite_code).deliver_later
      redirect_to admin_waitlist_signups_path, notice: "#{signup.email} invited with code #{invite_code.code}."
    end

    def convert
      signup = WaitlistSignup.find(params[:id])
      signup.mark_converted!
      redirect_to admin_waitlist_signups_path, notice: "#{signup.email} marked as converted."
    end

    def bulk_invite
      ids = params[:signup_ids] || []
      count = 0
      WaitlistSignup.where(id: ids, status: "waiting").find_each do |signup|
        invite_code = generate_invite_code(signup)
        signup.mark_invited!
        WaitlistMailer.invitation(signup, invite_code).deliver_later
        count += 1
      end
      redirect_to admin_waitlist_signups_path, notice: "#{count} signups invited."
    end

    # AJAX: communes for department
    def communes
      communes = Commune.where(department_id: params[:department_id]).order(:name)
      render json: communes.map { |c| { id: c.id, name: c.name } }
    end

    private

    def generate_invite_code(signup)
      InviteCode.create!(
        commune_id: signup.commune_id,
        code_type: "community",
        max_uses: 1,
        expires_at: 30.days.from_now,
        note: "Waitlist invite for #{signup.email}"
      )
    end
  end
end
