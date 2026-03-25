module Reviewers
  class PasswordsController < ApplicationController
    def new
      if current_reviewer  # Adjust to your auth method
        redirect_to reviewers_dashboard_path
      end
    end

    def create
      reviewer = Reviewer.find_by(email: params[:reviewer][:email])  # Adjust to your model (e.g., User with role)
      if reviewer
        reviewer.send_reset_password_instructions  # Assuming Devise or custom method
        flash[:notice] = "Password reset instructions sent."
      else
        flash[:alert] = "Email not found."
      end
      render :new
    end

    def edit
      self.resource = resource_class.new  # Devise-like; adjust if custom
    end

    def update
      if resource.update(password_params)
        flash[:notice] = "Password updated."
        redirect_to reviewers_login_path
      else
        render :edit
      end
    end

    private

    def reviewer_params
      params.require(:reviewer).permit(:email, :password, :password_confirmation)
    end
  end
end
