# app/controllers/visitors/visitor_base_controller.rb
class Visitors::VisitorBaseController < ApplicationController
  layout "visitor"

  protect_from_forgery with: :exception
end
