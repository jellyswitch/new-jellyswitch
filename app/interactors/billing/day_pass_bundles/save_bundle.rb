class Billing::DayPassBundles::SaveBundle
  include Interactor

  delegate :operator, :location, :params, :user_id, to: :context

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

    bundle = DayPassBundle.new(
      user: user,
      operator: operator,
      location: location,
      day_pass_type: day_pass_type,
      quantity_purchased: day_pass_type.quantity,
      passes_remaining: day_pass_type.quantity,
      purchased_at: Time.current
    )
    bundle.billable = BillableFactory.for(bundle).billable

    unless bundle.billable.has_stripe_customer_for_location?(location)
      context.fail!(message: "Cannot create paid day pass bundle for user without billing info.")
    end

    unless bundle.save
      context.fail!(message: "Unable to create day pass bundle.")
    end

    context.day_pass_bundle = bundle
  end

  def rollback
    context.day_pass_bundle&.destroy
  end
end
