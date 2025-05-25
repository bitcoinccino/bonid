require "test_helper"

class Admin::PartnerApplicationsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_partner_applications_index_url
    assert_response :success
  end

  test "should get show" do
    get admin_partner_applications_show_url
    assert_response :success
  end

  test "should get update" do
    get admin_partner_applications_update_url
    assert_response :success
  end
end
