require "test_helper"

class RoomsControllerTest < ActionDispatch::IntegrationTest

  setup do
    @user = users(:cowork_tahoe_admin)
    log_in @user
    @room = rooms(:small_meeting_room)
  end

  test "should get rooms index" do
    get rooms_path, env: default_env
    assert_response :success
  end

  test "new room path should redirect unauthorized users" do
    @user.update(role: "unassigned")
    get new_room_path, env: default_env
    assert_response 302
  end

  test "should show room" do
    get room_path(@room), env: default_env
    assert_response :success
  end

  test "should get new room path" do
    get new_room_path, env: default_env
    assert_response :success
  end

  test "should create a new room" do
    assert_difference "Room.count", 1 do
      post rooms_path, params: { room: { name: "tims room" } }, env: default_env
    end
    assert_not flash.empty?
    assert_response :found
    assert_redirected_to room_path(Room.last)
  end

  test "should not create room without a name" do
    room = Room.new
    assert_not room.save
  end

  test "should get room edit path" do
    get edit_room_path(@room), env: default_env
    assert_response :success
  end

  test "should update room" do
    patch room_path(@room), params: { room: { name: "updated room name" } }, env: default_env
    assert_redirected_to room_path(@room)
    assert_not flash.empty?
    @room.reload
    assert_equal "updated room name", @room.name
  end
end