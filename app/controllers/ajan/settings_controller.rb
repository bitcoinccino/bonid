# frozen_string_literal: true

# Ajan::SettingsController
# ========================
# Minimal agent account settings. v1 scope: change email only. Other account
# surfaces (password, phone, etc.) are added when explicitly asked.
module Ajan
  class SettingsController < Ajan::ApplicationController
    def edit
      @agent = current_agent
    end

    def update
      @agent = current_agent
      new_email = params.dig(:user, :email).to_s.strip.downcase

      if new_email.blank?
        flash.now[:alert] = "Tanpri antre yon nouvo imel."
        return render :edit, status: :unprocessable_entity
      end

      if new_email == @agent.email.to_s.downcase
        flash.now[:alert] = "Imel sa a se deja imel ou."
        return render :edit, status: :unprocessable_entity
      end

      if User.where.not(id: @agent.id).exists?(email: new_email)
        flash.now[:alert] = "Yon lòt kont itilize deja imel sa a."
        return render :edit, status: :unprocessable_entity
      end

      if @agent.update(email: new_email)
        redirect_to ajan_settings_path, notice: "Imel ou chanje."
      else
        flash.now[:alert] = @agent.errors.full_messages.to_sentence.presence || "Pa kapab chanje imel la."
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
