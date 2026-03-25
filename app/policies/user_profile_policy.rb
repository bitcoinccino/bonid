class UserProfilePolicy
  def initialize(user)
    @user = user
  end

  def complete?
    @user.first_name.present? &&
      @user.last_name.present? &&
      @user.sex.present? &&
      @user.dob.present? &&
      @user.id_type.present? &&
      @user.id_number.present? &&
      @user.health_profile&.blood_type.present? &&
      @user.address&.postal_code.present? &&
      @user.photo.attached?
  end

  def self.permitted_params
    [
      :first_name, :middle_name, :last_name, :sex, :dob, :phone,
      :email, :password, :password_confirmation, :marital_status, :social_handle,
      :street_address, :postal_code, :locality, :country, :id_type,
      :id_number, :place_of_birth, :nationality, :id_issued_on,
      :id_expires_on, :issuing_authority
    ]
  end
end
