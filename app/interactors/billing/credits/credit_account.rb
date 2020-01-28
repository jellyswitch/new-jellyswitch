class Billing::Credits::CreditAccount
  include Interactor

  delegate :amount, :user, :location, to: :context

  def call
    user.update(credit_balance: amount)
  end
end