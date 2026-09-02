require "test_helper"
require "day_office_helper"

# Staff "Add day pass" for a member: the type list shows every available type
# (paid ones included) even when the member has no card on file, and the comp
# checkbox mints the pass with no Stripe invoice or charge. Reported 9/1/2026
# by Tahoe Longhouse: the dropdown read as empty for a brand-new member
# because paid types were hidden behind the member's billing state.
class Operator::AdminDayPassCompTest < ActionDispatch::IntegrationTest
  include DayOfficeHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    host! "#{@operator.subdomain}.example.com"
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @paid = DayPassType.create!(operator: @operator, location: @location, name: "Private Office Day Pass",
                                  amount_in_cents: 10000, quantity: 1, available: true, visible: false)
      @free = DayPassType.create!(operator: @operator, location: @location, name: "$0 Day Pass",
                                  amount_in_cents: 0, quantity: 1, available: true, visible: false)
      @retired = DayPassType.create!(operator: @operator, location: @location, name: "Retired",
                                     amount_in_cents: 5000, quantity: 1, available: false, visible: true)
    end
  end

  def location_today
    tz = ActiveSupport::TimeZone[@location.time_zone.presence || "UTC"]
    Time.current.in_time_zone(tz).to_date
  end

  def day_params(type, comp: nil)
    d = location_today
    { day_pass: { "day(1i)" => d.year.to_s, "day(2i)" => d.month.to_s, "day(3i)" => d.day.to_s,
                  day_pass_type: type.id.to_s, user_id: @member.id.to_s, comp: comp }.compact }
  end

  test "form lists paid types for a member with no card on file" do
    log_in @admin

    get new_operator_admin_day_pass_path(user_id: @member.id), env: default_env

    assert_response :success
    assert_select "select[name='day_pass[day_pass_type]'] option[value=?]", @paid.id.to_s
    assert_select "select[name='day_pass[day_pass_type]'] option[value=?]", @free.id.to_s
    assert_select "select[name='day_pass[day_pass_type]'] option[value=?]", @retired.id.to_s, count: 0
    assert_select "input[name='day_pass[comp]']"
    assert_match "no card on file", response.body
  end

  test "comp mints a paid pass with no invoice and no Stripe call" do
    log_in @admin
    Stripe::InvoiceItem.expects(:create).never
    Stripe::Invoice.expects(:create).never

    assert_difference -> { @member.day_passes.count }, 1 do
      post operator_admin_day_passes_path, params: day_params(@paid, comp: "1"), env: default_env
    end

    assert_redirected_to user_path(@member)
    pass = @member.day_passes.order(:created_at).last
    assert_equal @paid, pass.day_pass_type
    assert_equal location_today, pass.day
    assert pass.complimentary?, "comp pass should be flagged complimentary"
    assert_nil pass.invoice_id
  end

  test "comp Day Office pass still books a pool room" do
    log_in @admin
    Stripe::InvoiceItem.expects(:create).never
    office_type, room_a, room_b = nil
    ActsAsTenant.with_tenant(@operator) do
      office_type = DayPassType.create!(operator: @operator, location: @location, name: "Day Office",
                                        amount_in_cents: 12500, quantity: 1, kind: "day_office",
                                        included_meeting_room_minutes: 0, available: true, visible: false)
      room_a = Room.create!(name: "Office A", operator: @operator, location: @location)
      room_b = Room.create!(name: "Office B", operator: @operator, location: @location)
      office_type.assign_office_rooms!({ room_a.id => 1, room_b.id => 2 })
    end

    post operator_admin_day_passes_path, params: day_params(office_type, comp: "1"), env: default_env

    assert_redirected_to user_path(@member)
    pass = @member.day_passes.order(:created_at).last
    assert pass.complimentary?
    hold = Reservation.find_by(day_office_pass_id: pass.id)
    assert hold, "office hold should be allocated for a comped Day Office pass"
    assert_includes [room_a.id, room_b.id], hold.room_id
  end

  test "member cannot forge a comp" do
    log_in @member

    post operator_admin_day_passes_path, params: day_params(@paid, comp: "1"), env: default_env

    assert_equal 0, @member.day_passes.complimentary.count, "member must not be able to mint a comp"
  end
end
