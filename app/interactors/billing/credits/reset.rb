class Billing::Credits::Reset
  include Interactor

  delegate :creditable, to: :context

  def call
    creditable.update(credit_balance: 0)
  end
end