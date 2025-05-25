class Admin::UsersController < Admin::ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def edit
    @user = User.find_by(id: params[:id])
    redirect_to admin_users_path, alert: "User not found." unless @user
  end

  def update
    @user = User.find_by(id: params[:id])
    if @user.nil?
      redirect_to admin_users_path, alert: "User not found."
    elsif @user.update(user_params)
      redirect_to admin_users_path, notice: "User updated."
    else
      render :edit
    end
  end

  private

  def require_admin!
    redirect_to root_path, alert: "Access denied." unless current_user.admin?
  end

  def user_params
    if current_user.admin?
      params.require(:user).permit(:email, :role_int)
    else
      params.require(:user).permit(:email)
    end
  end
end