# frozen_string_literal: true

# Minimal passwords controller for the Agent Portal scope. Inherits the
# full Devise flow; only exists so routes.rb's devise_for :agents can wire
# the ajan/passwords controller path instead of falling back to Devise's
# default (which would render under the generic layout).
module Ajan
  class PasswordsController < Devise::PasswordsController
    layout "ajan"
    helper AjanHelper
  end
end
