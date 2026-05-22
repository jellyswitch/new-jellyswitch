require "test_helper"

class Operator::ReservationsCalendarTest < ActionDispatch::IntegrationTest
  setup do
    @location = locations(:cowork_tahoe_location)
    @hidden_room = rooms(:large_meeting_room)
    @hidden_room.update!(visible: false)
    @visible_room = rooms(:small_meeting_room)
  end

  test "calendar room-filter shows hidden rooms to admins" do
    log_in users(:cowork_tahoe_admin)
    get calendar_reservations_path, env: default_env
    assert_response :success
    filter = css_select("#room-filter").first
    assert filter, "expected #room-filter select to render"
    option_names = filter.css("option").map { |o| o.text.strip }
    assert_includes option_names, @hidden_room.name
    assert_includes option_names, @visible_room.name
  end

  test "calendar room-filter hides hidden rooms from members" do
    log_in users(:cowork_tahoe_member)
    get calendar_reservations_path, env: default_env
    assert_response :success
    filter = css_select("#room-filter").first
    assert filter, "expected #room-filter select to render"
    option_names = filter.css("option").map { |o| o.text.strip }
    refute_includes option_names, @hidden_room.name
    assert_includes option_names, @visible_room.name
  end

  test "available_rooms JSON includes hidden room for admins" do
    log_in users(:cowork_tahoe_admin)
    get available_rooms_reservations_path,
        params: { date: Date.current.tomorrow.to_s, time: "10:00", duration: 60, day_or_night: "day" },
        env: default_env
    assert_response :success
    ids = JSON.parse(response.body).map { |r| r["id"] }
    assert_includes ids, @hidden_room.id
  end

  test "available_rooms JSON excludes hidden room for members" do
    log_in users(:cowork_tahoe_member)
    get available_rooms_reservations_path,
        params: { date: Date.current.tomorrow.to_s, time: "10:00", duration: 60, day_or_night: "day" },
        env: default_env
    assert_response :success
    ids = JSON.parse(response.body).map { |r| r["id"] }
    refute_includes ids, @hidden_room.id
  end
end
