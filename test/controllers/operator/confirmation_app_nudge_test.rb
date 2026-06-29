require "test_helper"

# Purchase/booking confirmation pages must carry the operator-dynamic app
# hand-off on the web (ADR 0017: redemption + door access live in the app, so a
# web buyer must be carried into it). Verified on the reservation confirmation —
# the canonical post-booking surface.
class Operator::ConfirmationAppNudgeTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe) # fixture has ios_url + android_url
    @location = locations(:cowork_tahoe_location)
    @user     = users(:cowork_tahoe_member)
    @room     = rooms(:small_meeting_room)
    host! "#{@operator.subdomain}.example.com"
  end

  def create_reservation
    create(:reservation, user: @user, room: @room, datetime_in: 1.day.from_now, hours: 1, minutes: 60, paid: true)
  end

  test "reservation confirmation shows the app hand-off on the web" do
    reservation = create_reservation
    log_in @user

    get reservation_path(reservation), env: default_env

    assert_response :success
    assert_select "#app-download-nudge"
    assert_select "a[href=?]", @operator.ios_url
    # Badges must use working local assets, not the dead linkmaker.itunes.apple.com
    # URL (that host no longer resolves — broken image).
    assert_select "#app-download-nudge img[src*=?]", "app-store-badge"
    assert_no_match(/linkmaker\.itunes\.apple\.com/, response.body)
  end

  test "no app hand-off when the operator has not configured store links" do
    @operator.update!(ios_url: nil, android_url: nil)
    reservation = create_reservation
    log_in @user

    get reservation_path(reservation), env: default_env

    assert_response :success
    assert_select "#app-download-nudge", count: 0
  end
end
