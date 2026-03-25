class Admin::UsersController < Admin::ApplicationController
  before_action before_action :authenticate_admin_user!


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

  def user_params
    # Only admins can access this controller, but keep explicit check
    if curren_admin_user
      params.require(:user).permit(:email, :role_int)
    else
      params.require(:user).permit(:email)
    end
  end
end
