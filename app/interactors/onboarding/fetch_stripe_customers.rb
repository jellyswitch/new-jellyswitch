class Onboarding::FetchStripeCustomers
  include Interactor

  delegate :location, to: :context

  def call
    stripe_data = location.retrieve_stripe_customers

    users_by_stripe_id = UserPaymentProfile
      .where.not(stripe_customer_id: nil)
      .includes(:user)
      .index_by(&:stripe_customer_id)

    customers = []
    stripe_data.auto_paging_each do |cust|
      customers << {
        stripe_customer_id: cust.id,
        user: users_by_stripe_id[cust.id]&.user,
        email: cust.email,
        card_added: card_added?(cust),
        name: cust.name,
      }
    end
    context.customers = customers
  end

  private

  def card_added?(stripe_customer)
    if stripe_customer && stripe_customer.sources && stripe_customer.sources.data
      if stripe_customer.sources.data.count < 1
        false
      else
        cards = stripe_customer.sources.data.select { |source| source.object == "card" }
        if cards.first
          if cards.first.respond_to? :last4
            true
          else
            false
          end
        else
          false
        end
      end
    else
      false
    end
  end
end