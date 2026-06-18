module Concierge
  # Phase 3: a public (no-login) "create account + buy a day pass" flow the
  # Concierge hands off to. Reuses the existing billing chain — Users::Create
  # (account + Stripe customer) then UpdatePaymentAndCreateDayPass (attach the
  # collected card + charge). No new billing logic.
  #
  # context in:  operator, location, day_pass_type, email, name, password, token (Stripe), day?
  # context out: user, day_pass  |  on failure: error (account_exists/account/payment) + message
  class PublicDayPassCheckout
    include Interactor

    def call
      email = context.email.to_s.downcase.strip

      if User.where(operator: context.operator).exists?(["lower(email) = ?", email])
        context.fail!(error: "account_exists",
                      message: "That email already has an account — please sign in to buy.")
      end

      user = create_account(email)
      purchase_day_pass(user)

      context.user = user
    end

    private

    def create_account(email)
      result = Users::Create.call(
        params: { email: email, name: context.name.presence || email,
                  password: context.password, original_location_id: context.location.id },
        operator: context.operator,
        admin_created: false,
      )
      context.fail!(error: "account", message: result.message) unless result.success?
      result.user
    end

    def purchase_day_pass(user)
      day = context.day || Date.current
      result = Billing::DayPasses::UpdatePaymentAndCreateDayPass.call(
        user_id: user.id,
        token: context.token,
        operator: context.operator,
        location: context.location,
        params: {
          day_pass_type: context.day_pass_type.id.to_s,
          day: day,
          operator_id: context.operator.id,
        },
      )
      # The account exists now even if the charge fails — they can sign in and
      # retry payment. Surfacing a clear error beats a silent half-purchase.
      context.fail!(error: "payment", message: result.message) unless result.success?
      context.day_pass = result.day_pass
    end
  end
end
