class Billing::Credits::Reset
  include Interactor

  delegate :creditable, to: :context

  def call
    context.old_credit_balance = creditable.credit_balance
    creditable.update(credit_balance: 0)
  end

  def rollback
    creditable.update(credit_balance: context.old_credit_balance)
  end
end