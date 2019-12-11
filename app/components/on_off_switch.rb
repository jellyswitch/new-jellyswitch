class OnOffSwitch < ApplicationComponent
  def initialize(predicate:, path:)
    @predicate = predicate
    @path = path
  end

  private

  attr_reader :predicate, :path
  
  def icon_class
    if predicate
      "fas fa-toggle-on"
    else
      "fas fa-toggle-off"
    end
  end
end