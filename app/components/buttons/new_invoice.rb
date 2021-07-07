class Buttons::NewInvoice < ApplicationComponent
  def initialize(user: nil, classes: "")
    @user = user
    @classes = classes
  end

  private
  
  attr_reader :user, :classes
end