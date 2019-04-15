class CreateDayPass
  include Interactor
  include FeedItemCreator

  delegate :day_pass, :token, :operator, :out_of_band, :params, :user_id, to: :context

  def call
    user = User.find(user_id)
    if user.nil?
      context.fail!(message: "No such user with ID #{user_id}")
    end

    if !user.has_stripe_customer?
      context.fail!(message: "Cannot create day pass for user without stripe customer.")
    end

    day_pass_type = DayPassType.find(params[:day_pass_type].to_i)
    if day_pass_type.nil?
      context.fail!(message: "Invalid day pass type.")
    end

    day_pass = DayPass.new(params.merge({day_pass_type: day_pass_type}))
    day_pass.user = user

    if token
      result = UpdateUserPayment.call(
        user: user,
        token: token
      )

      if !result.success?
        context.fail!(message: "Unable to update payment method.")
      end
    end

    @invoice_item = Stripe::InvoiceItem.create({
      customer: user.stripe_customer_id,
      currency: 'usd',
      amount: day_pass_type.amount_in_cents,
      description: day_pass.charge_description
    }, {
      api_key: operator.stripe_secret_key,
      stripe_account: operator.stripe_user_id
    })

    if out_of_band
      @invoice = Stripe::Invoice.create({
        customer: user.stripe_customer_id,
        billing: 'send_invoice',
        days_until_due: 30,
        auto_advance: true
      }, {
        api_key: operator.stripe_secret_key,
        stripe_account: operator.stripe_user_id
      })
    else
      @invoice = Stripe::Invoice.create({
        customer: user.stripe_customer_id,
        billing: 'charge_automatically',
        auto_advance: true
      }, {
        api_key: operator.stripe_secret_key,
        stripe_account: operator.stripe_user_id
      })
    end

    result = CreateInvoice.call(stripe_invoice: @invoice)
    if !result.success?
      context.fail!(message: result.message)
    end

    day_pass.invoice_id = result.invoice.id
    if !day_pass.save
      context.fail!(message: "There was a problem invoicing this day pass.")
    end

    context.day_pass = day_pass
    begin
      blob = {type: "day-pass", day_pass_id: day_pass.id}
      create_feed_item(user.operator, user, blob)
    rescue => e
      Rollbar.error(e)
    end

    Notifications::DayPassNotification.call(user: user, operator: operator)
  end
end
