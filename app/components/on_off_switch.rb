class OnOffSwitch < ApplicationComponent
  def initialize(predicate:)
    @predicate = predicate
  end

  private

  attr_reader :predicate
  
  def icon_class
    if predicate
      "fas fa-toggle-on"
    else
      "fas fa-toggle-off"
    end
  end
end