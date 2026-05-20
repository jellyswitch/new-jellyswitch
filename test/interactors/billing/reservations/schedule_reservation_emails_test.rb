require "test_helper"

class Billing::Reservations::ScheduleReservationEmailsTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:room_reservation)
    @interactor = Billing::Reservations::ScheduleReservationEmails.new
    @interactor.context.reservation = @reservation
  end

  test "schedules reservation emails when reservation.paid? is true" do
    @reservation.update!(paid: true)

    ScheduleProductEmails.expects(:call).once

    @interactor.call
  end

  test "does NOT schedule reservation emails when reservation.paid? is false" do
    # Members, office members (lease holders), admins, GMs, CMs, and
    # superadmins all get paid=false (see
    # User#should_charge_for_reservation?). The drip campaign is for
    # hourly + overage payers only — they shouldn't see onboarding /
    # follow-up nudges intended for one-off paid bookers.
    @reservation.update!(paid: false)

    ScheduleProductEmails.expects(:call).never

    @interactor.call
  end

  test "does NOT schedule reservation emails when reservation.paid is nil" do
    @reservation.update_column(:paid, nil)

    ScheduleProductEmails.expects(:call).never

    @interactor.call
  end

  test "does NOT schedule reservation emails when reservation is missing" do
    @interactor.context.reservation = nil

    ScheduleProductEmails.expects(:call).never

    @interactor.call
  end
end
