# app/controllers/visitors/visitor_auth_controller.rb
class Visitors::VisitorAuthController < ApplicationController
  layout "visitor_auth"

  protect_from_forgery with: :exception
end
