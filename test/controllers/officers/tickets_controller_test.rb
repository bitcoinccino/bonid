require "test_helper"

class Officers::TicketsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get officers_tickets_new_url
    assert_response :success
  end

  test "should get create" do
    get officers_tickets_create_url
    assert_response :success
  end

  test "should get index" do
    get officers_tickets_index_url
    assert_response :success
  end

  test "should get show" do
    get officers_tickets_show_url
    assert_response :success
  end
end
