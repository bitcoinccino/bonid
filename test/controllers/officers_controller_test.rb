require "test_helper"

class OfficersControllerTest < ActionDispatch::IntegrationTest
  test "should get accept_invitation" do
    get officers_accept_invitation_url
    assert_response :success
  end
end
