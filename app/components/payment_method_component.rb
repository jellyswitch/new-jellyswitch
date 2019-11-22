class PaymentMethodComponent < ApplicationComponent
  def initialize(user:)
    @user = user
  end

  private

  attr_reader :user
end