# frozen_string_literal: true

module Ajan
  module Cep
    class PollingCentersController < Ajan::ApplicationController
      def index
        @polling_centers = PollingCenter.order(:name).limit(50)
      end
    end
  end
end
