require "test_helper"
require "stripe_mock"

# T7: Billing::DayPasses::AllocateDayOffice runs immediately after SaveDayPass
# in every day-pass purchase organizer (ADR 0026) — allocation must succeed
# BEFORE any money moves, and its rollback rides the organizer's unwind when a
# later step (the Stripe charge) fails. See app/interactors/billing/day_passes/
# allocate_day_office.rb.
class Billing::DayPasses::AllocateDayOfficeTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(working_day_start: "08:00", working_day_end: "18:00")

    @office_type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                       kind: "day_office", amount_in_cents: 7500,
                                       included_meeting_room_minutes: 0, available: true, visible: true)
    @room_a = Room.create!(name: "Office A", operator: @operator, location: @location)
    @room_b = Room.create!(name: "Office B", operator: @operator, location: @location)
    @office_type.assign_office_rooms!({ @room_a.id => 1, @room_b.id => 2 })

    # suggested_standard_for's fallback branch (no default_for_room_booking
    # winner) tiebreaks on cheapest-then-id, and fixtures already give this
    # operator a $200 standard type — default_for_room_booking: true wins
    # outright over that branch, so this is THE unambiguous fallback no
    # matter what else exists.
    @standard_type = DayPassType.create!(name: "Standard Fallback", operator: @operator, location: @location,
                                         kind: "standard", amount_in_cents: 5000, available: true, visible: true,
                                         default_for_room_booking: true)

    @user = users(:cowork_tahoe_member)
    @other = users(:cowork_tahoe_non_member)
    @day = Date.current + 7

    StripeMock.start
    # NotifiableFactory (CreateNotifications, run after a successful charge)
    # pushes over HTTP; WebMock blocks unstubbed net connect.
    stub_request(:post, "https://fcm.googleapis.com/fcm/send").to_return(status: 200)
  end

  # --- helpers ---------------------------------------------------------

  # Gives `user` a real (StripeMock) customer + attached card for @location,
  # so ChargeDayPassInvoice's charge_invoice finds a payment method and can
  # actually succeed or be made to decline. Fixtures already stamp cowork_tahoe
  # member/non-member with a placeholder stripe_customer_id (user_payment_profiles.yml)
  # that was never actually minted in THIS test's fresh StripeMock backend, so
  # retrieving it 404s — create a real customer here and overwrite the
  # placeholder rather than relying on SaveDayPass's has_stripe_customer_for_location?
  # check to lazily provision one (it would find the stale fixture id and stop).
  def attach_card!(user)
    token = StripeMock.create_test_helper.generate_card_token
    customer = Stripe::Customer.create(
      { email: user.email, source: token },
      { api_key: @location.stripe_secret_key, stripe_account: @location.stripe_user_id }
    )
    user.update_stripe_customer_id_for_location(@location, customer.id)
    user.update_card_added_for_location(@location, true)
  end

  # Books every pool room solid for the whole posted-hours span on `day`, so
  # DayOffices::Allocator has nothing free to hand out.
  def fill_pool!(day = @day)
    span = @location.posted_hours_span(day)
    [@room_a, @room_b].each do |room|
      Reservation.create!(user: @other, room: room, datetime_in: span.first, minutes: 600)
    end
  end

  def purchase_params(type, day: @day, token: nil)
    {
      user_id: @user.id, token: token, operator: @operator, location: @location,
      params: { day_pass_type: type.id.to_s, day: day, operator_id: @operator.id },
    }
  end

  # --- tests -------------------------------------------------------------

  test "happy path: CreateDayPass allocates a pool room for a paid office pass" do
    attach_card!(@user)

    result = Billing::DayPasses::CreateDayPass.call(**purchase_params(@office_type))

    assert result.success?, "expected success, got: #{result.message}"
    assert result.day_pass.persisted?
    assert_equal @room_a, result.day_pass.office_hold.room
    assert result.office_hold.present?
    assert_equal result.office_hold.id, result.day_pass.reload.office_hold.id
  end

  test "sold out: fails before payment, surfaces a fallback type, persists nothing" do
    fill_pool!

    result = nil
    assert_no_difference ["DayPass.count", "Invoice.count"] do
      result = Billing::DayPasses::CreateDayPass.call(**purchase_params(@office_type))
    end

    assert result.failure?
    assert_equal :sold_out, result.outcome
    assert_equal @standard_type, result.fallback_day_pass_type
    assert_includes result.message, "Day Offices are fully booked for #{@day.strftime('%B %e')}. Try another day."
  end

  test "charge failure rollback: a declined charge releases the pool room and leaves no pass" do
    attach_card!(@user)
    # Targets the exact handler Stripe::Invoice#pay hits (POST /v1/invoices/:id/pay)
    # so only the charge itself declines — allocation and invoicing must have
    # already succeeded for this to be a meaningful "declined charge" case
    # rather than an incidental earlier failure.
    StripeMock.prepare_card_error(:card_declined, :pay_invoice)

    result = Billing::DayPasses::CreateDayPass.call(**purchase_params(@office_type))

    assert result.failure?
    assert_not DayPass.exists?(user: @user, day: @day)
    # Reservation's default_scope already excludes cancelled rows; spelled out
    # here to make the "hold was released" assertion explicit.
    assert_equal 0, Reservation.where(room_id: [@room_a.id, @room_b.id], cancelled: false).count
  end

  test "standard type: interactor no-ops" do
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator, location: @location,
                           day_pass_type: day_pass_type(:cowork_tahoe_day_pass_type), day: @day, imported: true)

    result = nil
    assert_no_difference "Reservation.count" do
      result = Billing::DayPasses::AllocateDayOffice.call(day_pass: pass)
    end
    assert result.success?
  end

  test "free path: CreateFreeDayPass with a $0 office type allocates too" do
    # FindFreeDayPass's real contract, discovered empirically (it's unreferenced
    # by any controller — grep confirms zero live callers):
    #
    # 1. DayPassType.for_operator(operator).free.available.first — no kind or
    #    location filter at all, so it isn't day-office-aware. Fixtures already
    #    give cowork_tahoe operator a free STANDARD type (free_day_pass_type
    #    fixture); fixture-assigned ids are always below anything create!'d in
    #    a test (Rails resets the pk sequence above the fixture max after
    #    loading), so that fixture always wins `.first` over a freshly created
    #    free office type. Neutralize it so this test can reach the free+office
    #    scenario the spec calls for.
    #
    # 2. Unlike the other 4 organizers' controller callers (which thread
    #    operator_id explicitly through `params`), FindFreeDayPass's own
    #    context.params = { day_pass_type:, day: } never sets operator_id — it
    #    relies entirely on acts_as_tenant's implicit assignment from
    #    ActsAsTenant.current_tenant. Called bare (as CreateDayPass's tests
    #    above are), SaveDayPass's day_pass.save fails "Operator must exist".
    #    So this path REQUIRES an ActsAsTenant.with_tenant wrapper that a real
    #    caller would normally get for free from the request-level tenant
    #    middleware — a real, load-bearing (if currently unexercised) gap.
    day_pass_type(:free_day_pass_type).update!(available: false)

    free_office_type = DayPassType.create!(name: "Free Day Office", operator: @operator, location: @location,
                                           kind: "day_office", amount_in_cents: 0,
                                           included_meeting_room_minutes: 0, available: true, visible: true)
    free_office_type.assign_office_rooms!({ @room_a.id => 1, @room_b.id => 2 })

    result = ActsAsTenant.with_tenant(@operator) do
      Billing::DayPasses::CreateFreeDayPass.call(user: @user, location: @location)
    end

    assert result.success?, "expected success, got: #{result.message}"
    assert_equal free_office_type, result.day_pass.day_pass_type
    assert result.day_pass.office_hold.present?
    assert_equal @room_a, result.day_pass.office_hold.room
  end

  test "day_passes.reservation_id stays nil on an allocated office pass" do
    # Pins the trap: the hold linkage is exclusively reservations.day_office_pass_id.
    # day_passes.reservation_id means ADR 0019 booking coverage — RescindForInvoice
    # skips a pass with a live `reservation`, so pointing it at the hold would make
    # a refunded office pass unrescindable.
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator, location: @location,
                           day_pass_type: @office_type, day: @day, imported: true)

    result = Billing::DayPasses::AllocateDayOffice.call(day_pass: pass)

    assert result.success?
    assert result.office_hold.present?
    assert_nil pass.reload.reservation_id
  end

  test "an office hold on a paid-capable pool room does not stamp meeting_room interest" do
    # Reservation#record_meeting_room_interest gates on room.paid_room? alone
    # (rentable + hourly_rate_in_cents > 0), not on reservation.paid — and an
    # office hold's room is whatever the pool happens to contain, which could
    # be a room that's ALSO bookable/priced for meetings. A $0 office hold is
    # not a meeting-room purchase signal (ADR 0026), so it must not tag one.
    paid_room = Room.create!(name: "Paid-capable Office", operator: @operator, location: @location,
                             rentable: true, hourly_rate_in_cents: 2500)
    assert paid_room.paid_room?, "sanity: pool room must actually be paid_room? for this test to mean anything"
    @office_type.assign_office_rooms!({ paid_room.id => 1 })

    pass = DayPass.create!(user: @user, billable: @user, operator: @operator, location: @location,
                           day_pass_type: @office_type, day: @day, imported: true)

    result = Billing::DayPasses::AllocateDayOffice.call(day_pass: pass)

    assert result.success?
    assert_equal paid_room, result.office_hold.room
    assert_not InterestTag.exists?(user: @user, product: "meeting_room"),
               "an office hold must not be recorded as meeting-room interest"
  end
end
