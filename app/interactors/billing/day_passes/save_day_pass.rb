class Billing::DayPasses::SaveDayPass
  include Interactor

  delegate :day_pass, :token, :operator, :location, :out_of_band, :params, :user_id, to: :context

  def call
    user = User.find_by(id: user_id)
    if user.nil?
      context.fail!(message: "No such user with ID #{user_id}")
    end
    context.user = user

    day_pass_type = DayPassType.find_by(id: params[:day_pass_type].to_i)
    if day_pass_type.nil?
      context.fail!(message: "Invalid day pass type.")
    end

    day_pass = DayPass.new(params.merge({ day_pass_type: day_pass_type }))
    day_pass.user = user
    day_pass.location = location
    day_pass.billable = BillableFactory.for(day_pass).billable

    # A comp never bills, so it needs no Stripe customer. It is recorded as
    # complimentary so revenue reports and the timeline read it right.
    day_pass.complimentary = true if context.comp

    unless day_pass_type.free? || context.comp || day_pass.billable.has_stripe_customer_for_location?(location)
      context.fail!(message: "Cannot create paid day pass for user without billing info.")
    end

    if !day_pass.save
      context.fail!(message: "Unable to create day pass.")
    end

    context.day_pass = day_pass
  end

  def rollback
    # after_create logged "Bought a day pass" the moment the row saved. When a
    # later organizer step fails (office allocation, the charge), the pass is
    # unwound here but that timeline entry stayed behind pointing at nothing —
    # TLH saw three "Bought a day pass · no room time booked" rows from three
    # failed attempts. Take the log entry down with the pass.
    Activity.where(subject: context.day_pass).delete_all
    context.day_pass.destroy
  end
end
