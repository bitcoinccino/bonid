require "test_helper"

class PartnerApplicationsControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get partner_applications_create_url
    assert_response :success
  end
end
