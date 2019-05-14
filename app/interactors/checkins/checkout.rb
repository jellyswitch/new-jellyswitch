class Checkins::Checkout
  include Interactor

  delegate :checkin, to: :context

  def call
    if !checkin.update(datetime_out: Time.current)
      context.fail!(message: "Could not check out.")
    end
  end
end