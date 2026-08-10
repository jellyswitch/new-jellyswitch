require "test_helper"
require "stripe_mock"

# Billing::DayPasses::NotifyDayOfficeAssigned is the LAST step of every day-pass
# purchase organizer (ADR 0026). Its whole reason for existing is timing: the
# hold is taken second (before money moves), but the confirmation email must
# only exist if the charge cleared — an email can't be unsent when the
# organizer unwinds.
#
# This file also pins the product-email automation: an office pass is still a
# day pass, and buying one must schedule exactly the same operator-authored
# emails a standard pass does.
class Billing::DayPasses::NotifyDayOfficeAssignedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "08:00", working_day_end: "18:00")

    @office_type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                       kind: "day_office", amount_in_cents: 7500,
                                       included_meeting_room_minutes: 0, available: true, visible: true)
    @standard_type = DayPassType.create!(name: "Day Pass", operator: @operator, location: @location,
                                         amount_in_cents: 3500, included_meeting_room_minutes: 0,
                                         available: true, visible: true)
    @room_a = Room.create!(name: "Office A", operator: @operator, location: @location)
    @room_b = Room.create!(name: "Office B", operator: @operator, location: @location)
    @office_type.assign_office_rooms!({ @room_a.id => 1, @room_b.id => 2 })

    @user = users(:cowork_tahoe_member)
    @other = users(:cowork_tahoe_non_member)
    @day = Date.current + 7

    StripeMock.start
    # CreateNotifications pushes over HTTP inside the organizer; WebMock blocks
    # unstubbed net connect.
    stub_request(:post, "https://fcm.googleapis.com/fcm/send").to_return(status: 200)
  end

  # --- helpers -----------------------------------------------------------

  # Mirrors Billing::DayPasses::AllocateDayOfficeTest#attach_card! — fixtures
  # carry a placeholder stripe_customer_id that doesn't exist in THIS test's
  # fresh StripeMock backend, so mint a real one and overwrite it.
  def attach_card!(user)
    token = StripeMock.create_test_helper.generate_card_token
    customer = Stripe::Customer.create(
      { email: user.email, source: token },
      { api_key: @location.stripe_secret_key, stripe_account: @location.stripe_user_id }
    )
    user.update_stripe_customer_id_for_location(@location, customer.id)
    user.update_card_added_for_location(@location, true)
  end

  def purchase_params(type, user: @user, day: @day)
    {
      user_id: user.id, token: nil, operator: @operator, location: @location,
      params: { day_pass_type: type.id.to_s, day: day, operator_id: @operator.id },
    }
  end

  def confirmation_email_count
    enqueued_jobs.count do |job|
      job[:job].to_s.include?("MailDeliveryJob") &&
        job[:args][0] == "UserMailer" && job[:args][1] == "day_office_confirmation"
    end
  end

  def product_email_jobs
    enqueued_jobs.select { |job| job[:job] == SendProductEmailJob }
  end

  def enable_product_templates!(product_type)
    ActsAsTenant.with_tenant(@operator) do
      %w[onboarding follow_up].each do |email_type|
        ProductEmailTemplate.create!(
          operator: @operator, location: @location, product_type: product_type,
          email_type: email_type, subject: "#{product_type} #{email_type}",
          follow_up_delay_days: (email_type == "follow_up" ? 2 : nil),
          enabled: true, body: "<p>Hello</p>"
        )
      end
    end
  end

  # --- email timing ------------------------------------------------------

  test "a successful office purchase enqueues exactly one confirmation email" do
    attach_card!(@user)

    result = Billing::DayPasses::CreateDayPass.call(**purchase_params(@office_type))

    assert result.success?, "expected success, got: #{result.message}"
    assert_equal 1, confirmation_email_count
    assert_enqueued_email_with UserMailer, :day_office_confirmation, args: [result.day_pass.id]
    assert_enqueued_with(job: SendNotificationsJob, args: ->(a) { a[1] == "DayOfficeAssigned" })
  end

  test "a DECLINED office purchase enqueues no confirmation email at all" do
    attach_card!(@user)
    StripeMock.prepare_card_error(:card_declined, :pay_invoice)

    result = Billing::DayPasses::CreateDayPass.call(**purchase_params(@office_type))

    assert result.failure?
    assert_equal 0, confirmation_email_count,
                 "the tail step never runs on a failed charge — nothing may promise an office"
    types = enqueued_jobs.select { |j| j[:job] == SendNotificationsJob }.map { |j| j[:args].last }
    assert_empty types.grep(/DayOffice/)
  end

  test "a sold-out office purchase enqueues no confirmation email" do
    attach_card!(@user)
    span = @location.posted_hours_span(@day)
    [@room_a, @room_b].each do |room|
      Reservation.create!(user: @other, room: room, datetime_in: span.first, minutes: 600)
    end

    result = Billing::DayPasses::CreateDayPass.call(**purchase_params(@office_type))

    assert result.failure?
    assert_equal :sold_out, result.outcome
    assert_equal 0, confirmation_email_count
  end

  test "a standard day-pass purchase enqueues no office confirmation" do
    attach_card!(@user)

    result = Billing::DayPasses::CreateDayPass.call(**purchase_params(@standard_type))

    assert result.success?, "expected success, got: #{result.message}"
    assert_equal 0, confirmation_email_count
  end

  test "the tail step no-ops when the hold is gone by the time it runs" do
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator, location: @location,
                           day_pass_type: @office_type, day: @day, imported: true)
    # No allocation ever happened — office_hold is nil.
    result = Billing::DayPasses::NotifyDayOfficeAssigned.call(day_pass: pass)

    assert result.success?
    assert_equal 0, confirmation_email_count
  end

  # --- automation pin (a): office passes keep the day_pass automation ------

  test "an office purchase schedules the same product emails as a standard one" do
    enable_product_templates!("day_pass")
    attach_card!(@user)
    attach_card!(@other)

    office_result = Billing::DayPasses::CreateDayPass.call(**purchase_params(@office_type))
    assert office_result.success?, "office purchase failed: #{office_result.message}"
    office_jobs = product_email_jobs
    office_kinds = office_jobs.map { |j| j[:args][4] }.sort

    clear_enqueued_jobs

    standard_result = Billing::DayPasses::CreateDayPass.call(**purchase_params(@standard_type, user: @other))
    assert standard_result.success?, "standard purchase failed: #{standard_result.message}"
    standard_jobs = product_email_jobs
    standard_kinds = standard_jobs.map { |j| j[:args][4] }.sort

    assert_equal %w[follow_up onboarding], standard_kinds,
                 "sanity: a standard purchase must schedule both product emails"
    assert_equal standard_jobs.size, office_jobs.size
    assert_equal standard_kinds, office_kinds
    assert_equal "day_pass", office_jobs.first[:args][3],
                 "an office pass is still a day_pass to the automation layer"
  end

  # --- automation pin (b): office BUNDLES keep the bundle automation -------

  test "an office bundle purchase schedules the bundle onboarding email like a standard bundle" do
    enable_product_templates!("day_pass_bundle")
    attach_card!(@user)
    attach_card!(@other)

    office_pack = DayPassType.create!(name: "Office 5-Pack", operator: @operator, location: @location,
                                      kind: "day_office", amount_in_cents: 30000, quantity: 5,
                                      included_meeting_room_minutes: 0, available: true, visible: true)
    standard_pack = DayPassType.create!(name: "5-Pack", operator: @operator, location: @location,
                                        amount_in_cents: 15000, quantity: 5,
                                        included_meeting_room_minutes: 0, available: true, visible: true)

    office_result = Billing::DayPassBundles::CreateBundle.call(
      user_id: @user.id, token: nil, operator: @operator, location: @location,
      params: { day_pass_type: office_pack.id.to_s, operator_id: @operator.id })
    assert office_result.success?, "office bundle purchase failed: #{office_result.message}"
    office_jobs = product_email_jobs

    clear_enqueued_jobs

    standard_result = Billing::DayPassBundles::CreateBundle.call(
      user_id: @other.id, token: nil, operator: @operator, location: @location,
      params: { day_pass_type: standard_pack.id.to_s, operator_id: @operator.id })
    assert standard_result.success?, "standard bundle purchase failed: #{standard_result.message}"
    standard_jobs = product_email_jobs

    assert_equal ["onboarding"], standard_jobs.map { |j| j[:args][4] },
                 "sanity: bundle purchases schedule onboarding only (review/replenishment are burn-fired)"
    assert_equal standard_jobs.map { |j| j[:args][4] }, office_jobs.map { |j| j[:args][4] }
    assert_equal "day_pass_bundle", office_jobs.first[:args][3]
    # Buying a pack takes no office — the days are scheduled later.
    assert_equal 0, confirmation_email_count
  end
end
