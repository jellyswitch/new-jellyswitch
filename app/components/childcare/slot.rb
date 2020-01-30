class Childcare::Slot < ApplicationComponent
  def initialize(childcare_slot:)
    @childcare_slot = childcare_slot
  end

  private

  attr_reader :childcare_slot

end