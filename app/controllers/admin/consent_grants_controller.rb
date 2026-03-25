module Admin
  class ConsentGrantsController < Admin::ApplicationController  # Or ApplicationController if no Admin base
    before_action :set_consent_grant, only: [ :show, :edit, :update, :destroy ]

    def index
      @consent_grants = ConsentGrant.all  # Adjust to ConsentGrant model
    end

    def show
    end

    def new
      @consent_grant = ConsentGrant.new
    end

    def create
      @consent_grant = ConsentGrant.new(consent_grant_params)

      if @consent_grant.save
        redirect_to @consent_grant, notice: "Consent grant created."
      else
        render :new
      end
    end

    def edit
    end

    def update
      if @consent_grant.update(consent_grant_params)
        redirect_to @consent_grant, notice: "Consent grant updated."
      else
        render :edit
      end
    end

    def destroy
      @consent_grant.destroy
      redirect_to consent_grants_url, notice: "Consent grant deleted."
    end

    private

    def set_consent_grant
      @consent_grant = ConsentGrant.find(params[:id])
    end

    def consent_grant_params
      params.require(:consent_grant).permit(:user_id, :partner_id, :scopes, :status, :granted_at, :expires_at)  # Adjust fields per schema
    end
  end
end
