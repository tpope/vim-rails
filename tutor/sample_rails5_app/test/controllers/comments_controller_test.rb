require 'test_helper'

class CommentsControllerTest < ActionDispatch::IntegrationTest
  test "gets index" do
    get comments_index_url
    assert_response :success
  end

  test "gets new" do
    get new_comments_url
    assert_response :success
  end
end

