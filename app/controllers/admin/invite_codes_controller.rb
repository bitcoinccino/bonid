# frozen_string_literal: true

module Admin
  class InviteCodesController < BaseController
    def index
      @codes = InviteCode.includes(:commune).order(created_at: :desc)
      @codes = @codes.where(code_type: params[:type]) if params[:type].present?
      @codes = @codes.where(active: params[:active] == "1") if params[:active].present?
      @codes = @codes.where(commune_id: params[:commune_id]) if params[:commune_id].present?
      @codes = @codes.where("code ILIKE ?", "%#{params[:search]}%") if params[:search].present?

      # Department cascade filter
      if params[:department_id].present?
        commune_ids = Commune.where(department_id: params[:department_id]).pluck(:id)
        @codes = @codes.where(commune_id: commune_ids)
      end

      @total = InviteCode.count
      @active_count = InviteCode.active.count
      @total_uses = InviteCode.sum(:uses_count)
      @departments = Department.order(:name)
      @communes = if params[:department_id].present?
                    Commune.where(department_id: params[:department_id]).order(:name)
                  else
                    Commune.order(:name)
                  end
      @codes = @codes.page(params[:page]).per(25)
    end

    def show
      @code = InviteCode.find(params[:id])
      @signups = WaitlistSignup.where(invite_code_used: @code.code)
    end

    def new
      @code = InviteCode.new(code_type: "community", max_uses: 50)
      @communes = Commune.order(:name)
    end

    def create
      @code = InviteCode.new(invite_code_params)
      if @code.save
        redirect_to admin_invite_codes_path, notice: "Invite code #{@code.code} created."
      else
        @communes = Commune.order(:name)
        render :new, status: :unprocessable_entity
      end
    end

    def toggle_active
      @code = InviteCode.find(params[:id])
      @code.update!(active: !@code.active)
      status = @code.active? ? "activated" : "deactivated"
      redirect_to admin_invite_codes_path, notice: "#{@code.code} #{status}."
    end

    def destroy
      @code = InviteCode.find(params[:id])
      if @code.uses_count > 0
        redirect_to admin_invite_codes_path, alert: "Cannot delete #{@code.code} because it has been used."
      else
        @code.destroy!
        redirect_to admin_invite_codes_path, notice: "#{@code.code} deleted."
      end
    end

    def bulk_generate
      commune_id = params[:commune_id]
      count = (params[:count] || 10).to_i.clamp(1, 100)
      max_uses = (params[:max_uses] || 1).to_i
      expires_in = params[:expires_in].present? ? params[:expires_in].to_i.days.from_now : nil

      created = 0
      count.times do
        code = InviteCode.new(
          commune_id: commune_id.presence,
          code_type: "community",
          max_uses: max_uses,
          expires_at: expires_in
        )
        created += 1 if code.save
      end

      redirect_to admin_invite_codes_path(commune_id: commune_id),
                  notice: "#{created} invite codes generated."
    end

    private

    def invite_code_params
      params.require(:invite_code).permit(:code_type, :commune_id, :max_uses, :expires_at, :note, :active)
    end
  end
end
