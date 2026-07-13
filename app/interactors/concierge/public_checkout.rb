module Concierge
  # Phase 3: a public (no-login) "create account + buy" flow the Concierge hands
  # off to. Reuses the existing billing chains — no new billing logic — and
  # routes by product: a single day pass, a bundle (DayPassType quantity>1), or
  # a membership (Plan). Membership is approval-gated downstream (the subscription
  # is created + charged here; building access waits on admin approval).
  #
  # context in:  operator, location, email, name, password, token (Stripe), and
  #              exactly one of: day_pass_type | plan
  # context out: user + one of (day_pass | day_pass_bundle | subscription)
  #              on failure: error (account_exists/account/payment) + message
  class PublicCheckout
    include Interactor

    def call
      email = context.email.to_s.downcase.strip

      if User.where(operator: context.operator).exists?(["lower(email) = ?", email])
        context.fail!(error: "account_exists",
                      message: "That email already has an account — please sign in to buy.")
      end

      user = create_account(email)

      if context.plan
        purchase_membership(user)
      elsif context.day_pass_type&.bundle?
        purchase_bundle(user)
      else
        purchase_day_pass(user)
      end

      context.user = user
    end

    private

    def create_account(email)
      result = Users::Create.call(
        params: {
          email: email, name: context.name.presence || email,
          password: context.password, phone: context.phone,
          original_location_id: context.location.id,
          # Virtual attr on User — Users::Save stamps terms_accepted_at when "1".
          # The checkout form requires the TOS checkbox before submit.
          terms_accepted: context.terms_accepted,
        },
        operator: context.operator,
        admin_created: false,
      )
      context.fail!(error: "account", message: result.message) unless result.success?
      result.user
    end

    def purchase_day_pass(user)
      day = context.day || Date.current
      day_pass_type = context.day_pass_type

      # Daily cap — the concierge widget is anonymous member self-serve, the
      # most public path in the app, so it gets the same gate as the four
      # logged-in member entry points. Staff paths stay ungated by design.
      if day_pass_type.daily_limit_reached?(day: day, location: context.location)
        context.fail!(message: "#{day_pass_type.name.pluralize} are fully booked for #{day.strftime('%B %e')}. Try another day.")
      end

      result = Billing::DayPasses::UpdatePaymentAndCreateDayPass.call(
        user_id: user.id, token: context.token, operator: context.operator, location: context.location,
        params: { day_pass_type: day_pass_type.id.to_s, day: day, operator_id: context.operator.id },
      )
      fail_payment!(result)
      context.day_pass = result.day_pass
    end

    def purchase_bundle(user)
      result = Billing::DayPassBundles::UpdatePaymentAndCreateBundle.call(
        user_id: user.id, token: context.token, operator: context.operator, location: context.location,
        params: { day_pass_type: context.day_pass_type.id.to_s },
      )
      fail_payment!(result)
      context.day_pass_bundle = result.day_pass_bundle
    end

    def purchase_membership(user)
      subscription = Subscription.new(plan: context.plan, subscribable: user)
      result = Billing::Subscription::UpdatePaymentAndCreateSubscription.call(
        subscription: subscription, token: context.token, user: user,
        start_day: Date.current, operator: context.operator, location: context.location,
      )
      fail_payment!(result)
      context.subscription = result.subscription
    end

    # The account exists now even if the charge fails — a clear error lets them
    # sign in and retry payment, which beats a silent half-purchase.
    def fail_payment!(result)
      context.fail!(error: "payment", message: result.message) unless result.success?
    end
  end
end
