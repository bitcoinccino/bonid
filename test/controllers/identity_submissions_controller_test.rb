require "test_helper"

class IdentitySubmissionsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get identity_submissions_new_url
    assert_response :success
  end

  test "should get create" do
    get identity_submissions_create_url
    assert_response :success
  end
end
