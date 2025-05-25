class UserMailer < ApplicationMailer
    default from: "no-reply@bonid.ht"
    def welcome_email(user)
      @user = user
      mail(to: @user.email, subject: "Welcome to BonID – Haiti's Open Digital Identity")
    end  
end


